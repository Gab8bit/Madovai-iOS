import Foundation

@MainActor
final class PoleDetailViewModel: ObservableObject {
    @Published private(set) var pole: Pole
    @Published private(set) var transits: [Transit] = []
    @Published private(set) var state: NetworkState = .loading
    @Published private(set) var lastUpdated: Date?

    private let transitsRepository: TransitsRepository
    private let astralTrainRepository: AstralTrainRepository
    private let poleCode: String
    private let vehicleTracker: VehicleTracker
    private let gtfsStore: GTFSStore
    private var transitsPollTask: Task<Void, Never>?

    /// Raw per-direction rail departures for this pole, from whichever tier
    /// actually produced data (see `refreshRailDepartures`) — not yet
    /// filtered to "still ahead of now", since that needs recomputing fresh
    /// on every view access, not just on every poll tick.
    @Published private(set) var railDirections: [AstralScheduleDirection] = []

    /// Today's remaining train departures for this pole, by direction — a
    /// 2-tier fallback:
    ///  1. ASTRAL (`AstralTrainRepository`) — the primary source for Cotral
    ///     rail: real per-run delay, cancellations, replacement-bus service.
    ///     Confirmed to catch trains PIV.do's own live endpoint can flat-out
    ///     omit (a dynamically-inserted reinforcement run at EUR Magliana
    ///     never appeared in PIV.do at all, live or scheduled, across two
    ///     consecutive polls).
    ///  2. The static GTFS timetable, only when ASTRAL resolves nothing at
    ///     all for this station (network failure, or a station name ASTRAL
    ///     doesn't recognize under any of this line's directions).
    /// nil when the pole isn't a rail one or neither tier has anything; a
    /// non-nil array can still have every direction's `entries` empty once
    /// today's service has finished.
    var scheduledDeparturesByDirection: [AstralScheduleDirection]? {
        guard pole.isTreno, !railDirections.isEmpty else { return nil }
        return railDirections
            .map { direction in
                AstralScheduleDirection(destination: direction.destination, entries: direction.entries.upcoming())
            }
            .sorted { $0.destination < $1.destination }
    }

    private var gtfsScheduledDirections: [AstralScheduleDirection]? {
        guard let stopId = pole.codiceStop,
              let departures = gtfsStore.scheduledDepartures(forRailStopId: stopId) else { return nil }
        let grouped = Dictionary(grouping: departures, by: \.destinationStopName)
        return grouped.map { destination, deps in
            AstralScheduleDirection(
                destination: destination,
                entries: deps.map {
                    AstralDeparture(id: $0.tripId, time: $0.departureTime, sortSeconds: $0.departureSeconds, delayMinutes: nil, isCancelled: false, isReplacementBus: false)
                }
            )
        }
    }

    init(
        pole: Pole,
        vehicleTracker: VehicleTracker,
        transitsRepository: TransitsRepository,
        gtfsStore: GTFSStore,
        astralTrainRepository: AstralTrainRepository
    ) {
        self.pole = pole
        self.poleCode = pole.codicePalina ?? pole.codiceStop ?? ""
        self.vehicleTracker = vehicleTracker
        self.transitsRepository = transitsRepository
        self.gtfsStore = gtfsStore
        self.astralTrainRepository = astralTrainRepository
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
        if pole.isTreno {
            await refreshRailDepartures()
            return
        }
        guard !poleCode.isEmpty else {
            state = .error("Codice palina mancante.")
            return
        }
        if transits.isEmpty { state = .loading }
        do {
            guard let result = try await transitsRepository.transits(poleCode: poleCode) else {
                transits = []
                state = .empty
                return
            }
            pole = mergedPole(base: pole, update: result.pole)
            transits = result.transits
                // A run whose real (delay-adjusted) arrival has already
                // passed by more than a couple minutes is stale data, not a
                // real upcoming arrival — Cotral's live feed can get stuck
                // reporting one (a transit that never actually arrives, with
                // `ritardo` climbing forever every poll) instead of ever
                // dropping it. `minutesFromNow` is delay-aware (see
                // `Transit.adjustedDisplayTime`), so a run that's a couple
                // minutes late but genuinely still on its way isn't
                // mistaken for "passed" just because its *original*
                // schedule time ticked by — that was a real bug here before
                // `minutesFromNow` accounted for delay. Same ~2min grace
                // `AtacRealtimeService` already applies to its own per-stop
                // predictions, applied here for every run (real-time,
                // monitored-offline, or schedule-only alike) so the whole
                // app agrees on what counts as "still upcoming".
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

    /// Rail poles never touch PIV.do at all — ASTRAL (tier 1) resolves every
    /// candidate direction of this pole's line by station name (see
    /// `CotralTrainRoute.directions(forGTFSRouteShortName:)`'s doc comment
    /// on why "every candidate" rather than an assumed pair: RVEXT alone now
    /// covers two direction pairs), keeping whichever ones actually match a
    /// station. Falls back to the static GTFS timetable (tier 2) only if
    /// ASTRAL resolves *nothing* for any direction — a genuine outage or a
    /// station name it doesn't recognize under this line at all.
    private func refreshRailDepartures() async {
        if railDirections.isEmpty { state = .loading }

        guard let stopId = pole.codiceStop,
              let railRoute = gtfsStore.getRoutesForStop(stopId).first(where: { $0.routeId.hasPrefix("F:") }),
              let candidates = CotralTrainRoute.directions(forGTFSRouteShortName: railRoute.routeShortName)
        else {
            state = .empty
            return
        }
        let stationName = pole.nomeStop ?? pole.nomePalina ?? ""
        guard !stationName.isEmpty else {
            state = .empty
            return
        }

        var resolved: [AstralScheduleDirection] = []
        for route in candidates {
            if let direction = try? await astralTrainRepository.departures(for: route, stationName: stationName) {
                resolved.append(direction)
            }
        }

        if resolved.isEmpty, let fallback = gtfsScheduledDirections {
            resolved = fallback
        }

        railDirections = resolved
        state = resolved.isEmpty ? .empty : .loaded
        lastUpdated = Date()
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
