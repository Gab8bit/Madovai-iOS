import SwiftUI

/// Shown when tapping an opportunistically-discovered Cotral vehicle marker
/// on the map. Cotral's live GPS endpoint has no per-run stop-by-stop
/// itinerary (checked directly against the API — several plausible command
/// variants all errored or returned nothing) and there's no confirmed way to
/// map this vehicle's internal run id to a GTFS trip, so this can't show
/// *this specific train's* remaining stops. It can, and does, show ASTRAL's
/// published timetable (the same primary source `PoleDetailViewModel` uses
/// per-station) for the vehicle's own direction — `vehicle.routeId` already
/// parses straight into a `CotralTrainRoute`, and ASTRAL takes exactly that
/// plus a station name, no shared vehicle/stop id needed. That's a genuine
/// schedule for this line and direction, with real delay/cancellation data,
/// just not proof-linked to this one vehicle (ASTRAL carries no train id
/// either, only times per station).
struct CotralVehicleDetailSheet: View {
    let vehicle: TransitVehicle
    let astralTrainRepository: AstralTrainRepository

    @State private var stations: [StationNextPassage] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    private var trainRoute: CotralTrainRoute? {
        vehicle.routeId.flatMap(CotralTrainRoute.init(rawValue:))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: vehicle.routeId) {
            await loadSchedule()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Carico l'orario della linea…")
            Spacer()
        } else if stations.isEmpty {
            Spacer()
            EmptyStateView(
                systemImage: "info.circle",
                title: loadFailed ? "Orario non disponibile" : "Itinerario del veicolo non disponibile",
                message: loadFailed
                    ? "Non è stato possibile recuperare l'orario di questa linea al momento."
                    : "Non risultano corse programmate per questa linea per il resto di oggi."
            )
            Spacer()
        } else {
            List {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Orario della linea, non di questa specifica corsa", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let trainRoute {
                        Text(trainRoute.directionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                ForEach(stations) { entry in
                    StationNextPassageRow(entry: entry)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadSchedule() async {
        guard let trainRoute else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let stationList = try await astralTrainRepository.stations(for: trainRoute)
            // Fan out one /api/transit call per station, concurrently (same
            // pattern as `CotralViewportVehicleService.scan()`'s per-pole
            // fan-out) — ASTRAL scopes a transit query to a single station,
            // unlike the old widget which returned every station's next
            // passage in one call.
            let nextByStation = await withTaskGroup(of: (String, AstralDeparture?).self) { group -> [String: AstralDeparture?] in
                for station in stationList {
                    group.addTask {
                        let direction = try? await astralTrainRepository.departures(for: trainRoute, stationName: station.nomeFermata)
                        return (station.nomeFermata, direction?.entries.upcoming().first)
                    }
                }
                var result: [String: AstralDeparture?] = [:]
                for await (name, next) in group { result[name] = next }
                return result
            }
            // Sorted by each station's own next-passage time, not physical
            // order — a station's very next train isn't necessarily the
            // same physical run as its neighbor's, so this is "what's
            // coming up next, anywhere on the line". Stations with nothing
            // left today sort to the bottom.
            stations = stationList
                .map { StationNextPassage(stationName: $0.nomeFermata, next: nextByStation[$0.nomeFermata] ?? nil) }
                .sorted { lhs, rhs in
                    let l = lhs.next?.sortSeconds ?? Int.max
                    let r = rhs.next?.sortSeconds ?? Int.max
                    return l < r
                }
        } catch {
            stations = []
            loadFailed = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: vehicle.kind.sfSymbolName)
                Text("Linea \(lineLabel)")
                    .font(.title3.bold())
            }
            Text("Cotral · posizione in tempo reale")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let delaySeconds = vehicle.delaySeconds, abs(delaySeconds) >= 60 {
                Text(delayLabel(delaySeconds))
                    .font(.caption)
                    .foregroundStyle(delaySeconds > 0 ? .red : .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    /// For a train, `routeLabel` is one of the internal `codicePercorso`
    /// values (e.g. "RL_PSP-CC") — not meaningful to a rider, so this shows
    /// the line's real name instead when recognized.
    private var lineLabel: String {
        if let routeId = vehicle.routeId, let trainRoute = CotralTrainRoute(rawValue: routeId) {
            return trainRoute.lineName
        }
        return vehicle.routeLabel ?? "—"
    }

    private func delayLabel(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return seconds > 0 ? "in ritardo di \(minutes) min" : "in anticipo di \(minutes) min"
    }
}

private struct StationNextPassage: Identifiable {
    let stationName: String
    let next: AstralDeparture?
    var id: String { stationName }
}

/// Same delay/cancelled/replacement-bus presentation as the per-station
/// schedule's own `AstralDepartureRow` (`PoleDetailSheet.swift`) — this list
/// shows one train's line-wide itinerary rather than one station's several
/// departures, so it can't share that view outright (no "Prossimo treno"
/// badge here, every row already *is* the next one for its station), but the
/// same ASTRAL fields deserve the same treatment rather than a bare time.
private struct StationNextPassageRow: View {
    let entry: StationNextPassage

    var body: some View {
        HStack {
            Text(entry.stationName)
                .font(.subheadline)
            Spacer()
            if let next = entry.next {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        if next.isReplacementBus {
                            Image(systemName: "bus").foregroundStyle(.secondary)
                        }
                        Text(next.time)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    if next.isCancelled {
                        Text("Soppressa")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red, in: Capsule())
                    } else if !delayText(next).isEmpty {
                        Text(delayText(next))
                            .font(.caption)
                            .foregroundStyle(delayColor(next))
                    }
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func delayText(_ departure: AstralDeparture) -> String {
        guard let minutes = departure.delayMinutes else { return "" }
        if abs(minutes) < 1 { return "puntuale" }
        return minutes > 0 ? "in ritardo di \(minutes) min" : "in anticipo di \(abs(minutes)) min"
    }

    private func delayColor(_ departure: AstralDeparture) -> Color {
        guard let minutes = departure.delayMinutes else { return .secondary }
        if abs(minutes) < 1 { return .secondary }
        return minutes > 0 ? .red : .green
    }
}
