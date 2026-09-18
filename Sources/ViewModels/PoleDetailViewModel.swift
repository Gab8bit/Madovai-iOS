import Foundation

@MainActor
final class PoleDetailViewModel: ObservableObject {
    @Published private(set) var pole: Pole
    @Published private(set) var transits: [Transit] = []
    @Published private(set) var state: NetworkState = .loading
    @Published private(set) var lastUpdated: Date?

    private let transitsRepository: TransitsRepository
    private let cotralTrainScheduleRepository: CotralTrainScheduleRepository
    private let poleCode: String
    private let vehicleTracker: VehicleTracker
    private let gtfsStore: GTFSStore
    private var transitsPollTask: Task<Void, Never>?
    private var isFetchingTrainWidget = false

    /// Tier 2 of the schedule fallback (see `scheduledDeparturesByDirection`)
    /// — the cotralspa.it widget's per-station passages for this pole's
    /// line, both directions, fetched once per "PIV.do has nothing" streak
    /// and cached until it either succeeds or the sheet closes. nil until a
    /// fetch has completed successfully for this pole.
    @Published private(set) var trainWidgetDirections: [TrainScheduleDirection]?

    /// Today's remaining train departures for this pole, by direction —
    /// tiers 2 and 3 of a 3-tier fallback:
    ///  1. Live PIV.do transits (`state == .loaded`, shown via the normal
    ///     `transitList`/`TransitRowView` elsewhere) — richer than either
    ///     tier below (genuine per-train delay, vehicle id, live/monitored
    ///     status) and always preferred when Cotral has it for this stop.
    ///  2. The cotralspa.it train-schedule widget (`trainWidgetDirections`),
    ///     consulted only once PIV.do comes back empty for this stop.
    ///  3. The static GTFS timetable, when tier 2 also has nothing (widget
    ///     unreachable, unparseable, or genuinely no data for this station).
    /// nil when the pole isn't a rail one or neither tier 2 nor 3 has
    /// anything at all; a non-nil array can still have every direction's
    /// `entries` empty once today's service has finished. Recomputed on
    /// every view refresh, so a departure naturally drops off once its time
    /// passes as the periodic transit poll ticks.
    var scheduledDeparturesByDirection: [TrainScheduleDirection]? {
        guard pole.isTreno else { return nil }
        let source = widgetHasData ? trainWidgetDirections : gtfsScheduledDirections
        guard let source else { return nil }

        let nowSeconds = Self.secondsSinceMidnight(Date())
        return source
            .map { direction in
                TrainScheduleDirection(
                    destination: direction.destination,
                    entries: direction.entries.filter { $0.sortSeconds >= nowSeconds }.sorted { $0.sortSeconds < $1.sortSeconds }
                )
            }
            .sorted { $0.destination < $1.destination }
    }

    /// Live PIV.do transits (tier 1) for a Cotral rail pole, split by
    /// direction instead of one mixed list — `Transit.percorso` for a train
    /// literally IS one of the 6 `codicePercorso` values
    /// (`CotralTrainRoute`'s raw value; confirmed PIV.do echoes the same
    /// code cotralspa.it's own widget uses), so it doubles as a clean
    /// direction key instead of the raw code being shown in the UI (see
    /// `TransitRowView.destinationLabel`). nil when the pole isn't a rail
    /// one, there are no live transits, or any transit's `percorso` doesn't
    /// parse as a known route (falls back to the plain unsplit
    /// `transitList` in that case, rather than silently dropping data).
    var liveTransitsByDirection: [(route: CotralTrainRoute, transits: [Transit])]? {
        guard pole.isTreno, !transits.isEmpty else { return nil }
        var byRoute: [CotralTrainRoute: [Transit]] = [:]
        for transit in transits {
            guard let route = CotralTrainRoute(rawValue: transit.percorso) else { return nil }
            byRoute[route, default: []].append(transit)
        }
        return byRoute.map { ($0.key, $0.value) }.sorted { $0.0.destinationName < $1.0.destinationName }
    }

    private var widgetHasData: Bool {
        trainWidgetDirections?.contains { !$0.entries.isEmpty } ?? false
    }

    private var gtfsScheduledDirections: [TrainScheduleDirection]? {
        guard let stopId = pole.codiceStop,
              let departures = gtfsStore.scheduledDepartures(forRailStopId: stopId) else { return nil }
        let grouped = Dictionary(grouping: departures, by: \.destinationStopName)
        return grouped.map { destination, deps in
            TrainScheduleDirection(
                destination: destination,
                entries: deps.map { TrainScheduleEntry(id: $0.tripId, time: $0.departureTime, sortSeconds: $0.departureSeconds) }
            )
        }
    }

    private static func secondsSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }

    init(
        pole: Pole,
        vehicleTracker: VehicleTracker,
        transitsRepository: TransitsRepository,
        gtfsStore: GTFSStore,
        cotralTrainScheduleRepository: CotralTrainScheduleRepository
    ) {
        self.pole = pole
        self.poleCode = pole.codicePalina ?? pole.codiceStop ?? ""
        self.vehicleTracker = vehicleTracker
        self.transitsRepository = transitsRepository
        self.gtfsStore = gtfsStore
        self.cotralTrainScheduleRepository = cotralTrainScheduleRepository
    }

    // MARK: - Transits polling

    func startObservingTransits() {
        guard transitsPollTask == nil else { return }
        transitsPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshTransits()
                try? await Task.sleep(nanoseconds: UInt64(Config.transitsPollInterval * 1_000_000_000))
            }
        }
    }

    func stopObservingTransits() {
        transitsPollTask?.cancel()
        transitsPollTask = nil
    }

    private func refreshTransits() async {
        guard !poleCode.isEmpty else {
            state = .error("Codice palina mancante.")
            return
        }
        if transits.isEmpty { state = .loading }
        do {
            guard let result = try await transitsRepository.transits(poleCode: poleCode) else {
                transits = []
                state = .empty
                if pole.isTreno, trainWidgetDirections == nil {
                    Task { await fetchTrainWidgetSchedule() }
                }
                return
            }
            pole = mergedPole(base: pole, update: result.pole)
            transits = result.transits
                // A run whose own displayed time has already passed by more
                // than a couple minutes is stale data, not a real upcoming
                // arrival — Cotral's live feed can get stuck reporting one
                // (a transit that never actually arrives, with `ritardo`
                // climbing forever every poll) instead of ever dropping it.
                // Same ~2min grace `AtacRealtimeService` already applies to
                // its own per-stop predictions, applied here for every run
                // (real-time, monitored-offline, or schedule-only alike) so
                // the whole app agrees on what counts as "still upcoming".
                .filter { ($0.minutesFromNow ?? 0) >= -2 }
                .sorted {
                    let a = $0.minutesFromNow ?? .max
                    let b = $1.minutesFromNow ?? .max
                    return a < b
                }
            state = .loaded
            lastUpdated = Date()

            // If the transit whose vehicle we're following is no longer
            // reporting isAlive, tell the shared tracker immediately rather
            // than waiting out its own position-poll miss threshold.
            if let followedCode = vehicleTracker.vehicleCode,
               let matching = transits.first(where: { $0.automezzo.codice == followedCode }),
               matching.automezzo.isAlive == false {
                vehicleTracker.reportOffline(for: followedCode)
            }
        } catch {
            state = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Tier 2 of the schedule fallback: queries the cotralspa.it widget for
    /// both directions of this pole's rail line and keeps whichever
    /// passages match this station by name. A network/parsing failure here
    /// just leaves `trainWidgetDirections` nil — `scheduledDeparturesByDirection`
    /// then falls through to tier 3 (GTFS) automatically, no error surfaced
    /// (this is a best-effort upgrade over the static schedule, not
    /// something the user needs to see fail).
    private func fetchTrainWidgetSchedule() async {
        guard !isFetchingTrainWidget else { return }
        isFetchingTrainWidget = true
        defer { isFetchingTrainWidget = false }

        guard let routes = trainRoutesForCurrentPole() else { return }
        let stationName = (pole.nomeStop ?? pole.nomePalina ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !stationName.isEmpty else { return }

        var directions: [TrainScheduleDirection] = []
        for route in routes {
            // Exact match first; GTFS and the widget don't always spell a
            // station the same way (confirmed: GTFS has "Acilia Sud", the
            // widget has "Acilia Sud - Dragona") — a substring match in
            // either direction recovers those cases without being so loose
            // it could cross-match two different stations.
            guard let stations = try? await cotralTrainScheduleRepository.schedule(for: route),
                  let match = stations.first(where: { $0.stationName.trimmingCharacters(in: .whitespaces).lowercased() == stationName })
                      ?? stations.first(where: { station in
                          let name = station.stationName.trimmingCharacters(in: .whitespaces).lowercased()
                          return name.contains(stationName) || stationName.contains(name)
                      })
            else { continue }

            let entries = match.passages.compactMap { passage -> TrainScheduleEntry? in
                guard let seconds = Self.secondsFromHHMM(passage.time) else { return nil }
                return TrainScheduleEntry(id: "\(route.rawValue)-\(passage.time)", time: passage.time, sortSeconds: seconds)
            }
            let destination = stations.last?.stationName ?? route.directionLabel
            directions.append(TrainScheduleDirection(destination: destination, entries: entries))
        }

        guard directions.contains(where: { !$0.entries.isEmpty }) else { return }
        trainWidgetDirections = directions
    }

    /// Which of the 6 `codicePercorso` values (both directions) serve this
    /// pole's rail line, resolved via GTFS route membership rather than the
    /// stop id — both Roma-Viterbo lines share the same "RN_" GTFS stop
    /// prefix, only the route tells them apart (see
    /// `CotralTrainRoute.directions(forGTFSRouteShortName:)`).
    private func trainRoutesForCurrentPole() -> [CotralTrainRoute]? {
        guard let stopId = pole.codiceStop else { return nil }
        guard let railRoute = gtfsStore.getRoutesForStop(stopId).first(where: { $0.routeId.hasPrefix("F:") }) else { return nil }
        return CotralTrainRoute.directions(forGTFSRouteShortName: railRoute.routeShortName)
    }

    private static func secondsFromHHMM(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 3600 + minutes * 60
    }

    /// The pole info returned alongside transits is often sparser (fewer
    /// fields) than what we already had from the GTFS-derived nearby-poles
    /// list — keep whichever value each field already has when the new one
    /// is missing.
    private func mergedPole(base: Pole, update: Pole) -> Pole {
        Pole(
            codicePalina: update.codicePalina ?? base.codicePalina,
            codiceStop: update.codiceStop ?? base.codiceStop,
            nomePalina: update.nomePalina ?? base.nomePalina,
            nomeStop: update.nomeStop ?? base.nomeStop,
            localita: update.localita ?? base.localita,
            comune: update.comune ?? base.comune,
            coordX: update.coordX ?? base.coordX,
            coordY: update.coordY ?? base.coordY,
            zonaTariffaria: update.zonaTariffaria ?? base.zonaTariffaria,
            distanza: update.distanza ?? base.distanza,
            destinazioni: base.destinazioni ?? update.destinazioni,
            isCotral: base.isCotral ?? update.isCotral,
            isCapolinea: update.isCapolinea ?? base.isCapolinea,
            isBanchinato: update.isBanchinato ?? base.isBanchinato,
            preferita: base.preferita ?? update.preferita,
            isTreno: base.isTreno
        )
    }
}
