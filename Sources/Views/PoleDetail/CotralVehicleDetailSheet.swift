import SwiftUI

/// Shown when tapping an opportunistically-discovered Cotral vehicle marker
/// on the map. Cotral's live GPS endpoint has no per-run stop-by-stop
/// itinerary (checked directly against the API — several plausible command
/// variants all errored or returned nothing) and there's no confirmed way to
/// map this vehicle's internal run id to a GTFS trip, so this can't show
/// *this specific train's* remaining stops. It can, and does, show the
/// cotralspa.it timetable widget (tier 2 of the same fallback
/// `PoleDetailViewModel` uses per-station) for the vehicle's own direction —
/// `vehicle.routeId` already parses straight into a `CotralTrainRoute`, and
/// the widget takes exactly that, no stop id needed. That's a genuine
/// published schedule for this line and direction, just not proof-linked to
/// this one vehicle (the widget carries no train id either, only times).
struct CotralVehicleDetailSheet: View {
    let vehicle: TransitVehicle
    let scheduleRepository: CotralTrainScheduleRepository

    @State private var stations: [CotralTrainStationSchedule] = []
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
                    : "Cotral non espone l'elenco delle fermate di questa specifica corsa tramite l'endpoint usato dall'app — solo la sua posizione live."
            )
            Spacer()
        } else {
            List {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Orario della linea da tabella, non di questa specifica corsa", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let trainRoute {
                        Text(trainRoute.directionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                ForEach(stationsByNextPassage, id: \.station.id) { entry in
                    HStack {
                        Text(entry.station.stationName)
                            .font(.subheadline)
                        Spacer()
                        if let next = entry.next {
                            Text(next.time)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    /// Stations sorted by their own next-passage time (ascending) rather
    /// than by physical position — a station's very next train isn't
    /// necessarily the same physical run as its neighbor's, so this list is
    /// "what's coming up next, anywhere on the line" rather than one train's
    /// itinerary. Stations with nothing left today sort to the bottom.
    private var stationsByNextPassage: [(station: CotralTrainStationSchedule, next: CotralTrainPassage?)] {
        stations
            .map { ($0, nextPassage($0)) }
            .sorted { lhs, rhs in
                let l = lhs.1.flatMap { Self.secondsFromHHMM($0.time) } ?? Int.max
                let r = rhs.1.flatMap { Self.secondsFromHHMM($0.time) } ?? Int.max
                return l < r
            }
    }

    private func loadSchedule() async {
        guard let trainRoute else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            stations = try await scheduleRepository.schedule(for: trainRoute)
        } catch {
            stations = []
            loadFailed = true
        }
    }

    /// The next scheduled passage from now, if any — same "today, still
    /// ahead of now" logic `PoleDetailViewModel.fetchTrainWidgetSchedule`
    /// already applies to this same widget's passages.
    private func nextPassage(_ station: CotralTrainStationSchedule) -> CotralTrainPassage? {
        let now = Self.secondsSinceMidnight(Date())
        return station.passages
            .compactMap { passage -> (CotralTrainPassage, Int)? in
                guard let seconds = Self.secondsFromHHMM(passage.time) else { return nil }
                return (passage, seconds)
            }
            .filter { $0.1 >= now }
            .min { $0.1 < $1.1 }
            .map(\.0)
    }

    private static func secondsSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }

    private static func secondsFromHHMM(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 3600 + minutes * 60
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

    /// For a train, `routeLabel` is one of the 6 internal `codicePercorso`
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
