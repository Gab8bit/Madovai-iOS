import SwiftUI

/// Loads and polls one Cotral pole: live PIV.do runs for a bus pole, the
/// station timetable (ASTRAL, GTFS fallback) for a rail station.
@MainActor
final class PoleSheetModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, empty, failed }

    @Published private(set) var pole: Pole
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var transits: [Transit] = []
    @Published private(set) var railDirections: [AstralScheduleDirection] = []
    /// "astral" | "gtfs" | "none" for a rail station.
    @Published private(set) var railSource: String?
    /// Message of the last failed refresh (data, if any, is kept on screen).
    @Published private(set) var errorMessage: String?

    private let api: MadovaiAPI
    private weak var tracker: VehicleTracker?
    private lazy var poller = Poller(interval: Config.transitsPollInterval) { [weak self] in
        await self?.refresh()
    }

    init(pole: Pole, tracker: VehicleTracker?, api: MadovaiAPI = .shared) {
        self.pole = pole
        self.tracker = tracker
        self.api = api
    }

    var hasData: Bool { pole.isTreno ? !railDirections.isEmpty : !transits.isEmpty }

    func start() { poller.start() }
    func stop() { poller.stop() }
    func retry() {
        if !hasData { phase = .loading }
        errorMessage = nil
        poller.refreshNow()
    }

    func refresh() async {
        guard let code = pole.codicePalina ?? pole.codiceStop else {
            phase = .failed
            errorMessage = "Codice palina mancante."
            return
        }
        do {
            if pole.isTreno {
                let response = try await api.rail(stopId: code)
                railSource = response.source
                railDirections = response.directions.sorted { $0.destination < $1.destination }
                phase = railDirections.isEmpty ? .empty : .loaded
            } else {
                let response = try await api.cotralTransits(pole: code)
                if let info = response.pole { pole = pole.merged(with: info) }
                let list = response.transits.upcomingSorted()
                transits = list
                phase = list.isEmpty ? .empty : .loaded
                if let tracker, let followed = tracker.vehicleCode,
                   let match = list.first(where: { $0.vehicleCode == followed }), !match.vehicleAlive {
                    tracker.reportOffline(for: followed)
                }
            }
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.userMessage
            if !hasData { phase = .failed }
        }
    }
}

struct PoleSheet: View {
    @StateObject private var model: PoleSheetModel
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var tracker: VehicleTracker
    @State private var selectedDirection: String?

    init(pole: Pole, favoritesStore: FavoritesStore, tracker: VehicleTracker) {
        _model = StateObject(wrappedValue: PoleSheetModel(pole: pole, tracker: tracker))
        self.favoritesStore = favoritesStore
        self.tracker = tracker
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: model.pole.displayName,
                subtitle: model.pole.subtitle,
                isFavorite: model.pole.codicePalina.map { favoritesStore.isFavorite($0) },
                toggleFavorite: { favoritesStore.toggle(model.pole) }
            )
            if let code = tracker.vehicleCode {
                trackingBanner(code: code)
            }
            if let error = model.errorMessage, model.hasData {
                StaleDataStrip(message: error, retry: model.retry)
            }
            Divider()
            MinuteTicker { now in
                content(now: now)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch model.phase {
        case .loading:
            LoadingStateView(message: model.pole.isTreno ? "Carico gli orari…" : "Carico i transiti…")
        case .failed:
            ErrorStateView(message: model.errorMessage ?? APIError.offline.message, retry: model.retry)
        case .empty:
            EmptyStateView(
                systemImage: "clock.badge.questionmark",
                title: "Nessun transito disponibile",
                message: model.pole.isTreno
                    ? "Al momento non risultano corse per questa stazione, in tempo reale né programmate, per il resto di oggi."
                    : "Riprova più tardi o controlla un'altra palina."
            )
            .frame(maxHeight: .infinity)
        case .loaded:
            if model.pole.isTreno {
                railSchedule(now: now)
            } else {
                List(model.transits) { transit in
                    TransitRow(
                        transit: transit,
                        now: now,
                        isFollowing: tracker.isFollowing(transit.vehicleCode),
                        onToggleFollow: {
                            guard let code = transit.vehicleCode else { return }
                            tracker.toggleFollowing(code, isTreno: model.pole.isTreno)
                        }
                    )
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func railSchedule(now: Date) -> some View {
        let directions = model.railDirections.map {
            AstralScheduleDirection(destination: $0.destination, route: $0.route, entries: $0.entries.upcoming(from: now))
        }
        if let current = directions.first(where: { $0.destination == selectedDirection }) ?? directions.first {
            let isEstimate = model.railSource != "astral" || !current.entries.contains { $0.delayMinutes != nil }
            VStack(spacing: 0) {
                if isEstimate {
                    Label("Orario stimato da tabella, non in tempo reale", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08))
                }
                if directions.count > 1 {
                    Picker("Direzione", selection: Binding(
                        get: { current.destination },
                        set: { selectedDirection = $0 }
                    )) {
                        ForEach(directions) { Text($0.destination).tag($0.destination) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                } else {
                    Text("Verso \(current.destination)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                if current.entries.isEmpty {
                    EmptyStateView(
                        systemImage: "moon.zzz",
                        title: "Corse terminate per oggi",
                        message: "Non risultano altre corse programmate verso \(current.destination) per il resto di oggi."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    let nextId = current.entries.first?.id
                    List(current.entries) { departure in
                        TrainDepartureRow(departure: departure, now: now, isNext: departure.id == nextId)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private func trackingBanner(code: String) -> some View {
        let isLost: Bool = { if case .lost = tracker.state { return true } else { return false } }()
        return HStack(spacing: 10) {
            Image(systemName: isLost ? "location.slash.fill" : "location.fill")
                .foregroundStyle(isLost ? .red : .orange)
            VStack(alignment: .leading, spacing: 1) {
                if isLost {
                    Text("Tracking interrotto").font(.footnote.weight(.semibold))
                    Text("Il veicolo \(code) non trasmette più la posizione").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Seguendo \(tracker.isTreno ? "treno" : "bus") \(code)").font(.footnote.weight(.semibold))
                    Text("Posizione aggiornata ogni \(Int(Config.vehiclePositionPollInterval))s").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Ferma") { tracker.stopFollowing() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background((isLost ? Color.red : Color.orange).opacity(0.12))
    }
}

/// One Cotral bus run.
struct TransitRow: View {
    let transit: Transit
    let now: Date
    let isFollowing: Bool
    var onToggleFollow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transit.displayTime.isEmpty ? "--:--" : transit.adjustedDisplayTime)
                    .font(.title3.bold().monospacedDigit())
                    .strikethrough(transit.isCancelled)
                if let relative = RelativeTime.label(minutes: transit.minutesFromNow(now: now), passedLabel: "in transito") {
                    Text(relative).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(transit.lineAndDestinationLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                statusRow
                if !transit.instradamento.isEmpty {
                    Text(transit.instradamento)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if transit.isCancelled {
                CapsuleTag(text: "Soppressa", color: .red)
            } else if transit.canTrackVehicle {
                Button(action: onToggleFollow) {
                    VStack(spacing: 4) {
                        Image(systemName: isFollowing ? "location.fill" : "location")
                        Text(isFollowing ? "Seguito" : "Segui").font(.caption2)
                    }
                    .frame(minWidth: 44)
                }
                .buttonStyle(.bordered)
                .tint(isFollowing ? .orange : .accentColor)
            }
        }
        .opacity(transit.isCancelled ? 0.6 : 1)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch transit.trackingStatus {
        case .realtime:
            let delay = RelativeTime.delayLabel(seconds: transit.ritardoSeconds)
            HStack(spacing: 5) {
                StatusDot(color: .green, pulse: true)
                Text("Real-time · \(delay?.text ?? "puntuale")")
                    .font(.caption)
                    .foregroundStyle(delay.map { $0.isLate ? Color.red : Color.green } ?? .secondary)
            }
        case .monitoredOffline:
            HStack(spacing: 5) {
                StatusDot(color: .yellow)
                Text("Tracciata, bus non in trasmissione").font(.caption).foregroundStyle(.secondary)
            }
        case .scheduled:
            HStack(spacing: 5) {
                StatusDot(color: .gray)
                Text("Schedulata, no real-time").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One train at a station (ASTRAL or timetable).
struct TrainDepartureRow: View {
    let departure: AstralDeparture
    let now: Date
    let isNext: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(departure.time)
                    .font(.title3.bold().monospacedDigit())
                if let relative = RelativeTime.label(minutes: RomeTime.minutesFromNow(departure.time, now: now)) {
                    Text(relative).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if !departure.isCancelled {
                    if let delay = RelativeTime.trainDelayLabel(minutes: departure.delayMinutes) {
                        HStack(spacing: 6) {
                            StatusDot(color: .green, pulse: true)
                            Text(delay.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(delay.tone.color)
                        }
                    } else {
                        HStack(spacing: 6) {
                            StatusDot(color: .gray)
                            Text("Schedulata").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                if departure.isReplacementBus {
                    Label("Bus sostitutivo", systemImage: "bus").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if departure.isCancelled {
                CapsuleTag(text: "Soppressa", color: .red)
            } else if isNext {
                CapsuleTag(text: "Prossimo treno")
            }
        }
        .opacity(departure.isCancelled ? 0.6 : 1)
        .padding(.vertical, 6)
    }
}

extension RelativeTime.DelayTone {
    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .late: return .red
        case .early: return .green
        }
    }
}
