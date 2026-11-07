import SwiftUI

// MARK: - Atac / Roma TPL stop

/// Live arrivals at one platform of a station (polled), with the scheduled
/// timetable as fallback when there are no live arrivals at all.
@MainActor
final class AtacStopSheetModel: ObservableObject {
    @Published private(set) var stops: [AtacStop]
    @Published var selectedStopId: String {
        didSet { if oldValue != selectedStopId { resetForSelection() } }
    }
    @Published private(set) var live: [AtacArrival]?
    @Published private(set) var scheduled: [AtacArrival] = []
    @Published private(set) var isLoadingScheduled = false
    @Published private(set) var errorMessage: String?

    let routeId: String?
    private let api: MadovaiAPI
    private var scheduledFor: String?
    private lazy var poller = Poller(interval: Config.transitsPollInterval) { [weak self] in
        await self?.refresh()
    }

    init(group: AtacStopGroup, api: MadovaiAPI = .shared) {
        self.stops = group.stops
        self.routeId = group.routeId
        self.selectedStopId = group.stops[0].stopId
        self.api = api
    }

    var selected: AtacStop { stops.first { $0.stopId == selectedStopId } ?? stops[0] }

    /// Arrivals of the line the sheet was opened from first, when known.
    var liveArrivals: [AtacArrival] { live ?? [] }

    func start() {
        poller.start()
        Task { await completePlatformsIfNeeded() }
    }

    func stop() { poller.stop() }

    func retry() {
        errorMessage = nil
        poller.refreshNow()
    }

    private func resetForSelection() {
        live = nil
        scheduled = []
        errorMessage = nil
        scheduledFor = nil
        poller.refreshNow()
    }

    /// A stop opened from a favorite or search knows only one platform:
    /// fetch the station's other platforms (with direction labels).
    private func completePlatformsIfNeeded() async {
        guard stops.count == 1 || stops.contains(where: { $0.headsign == nil }) else { return }
        guard let response = try? await api.atacStop(id: stops[0].stopId, route: routeId), !response.stops.isEmpty else { return }
        let resolved = response.stops.map(\.asAtacStop)
        if resolved.contains(where: { $0.stopId == selectedStopId }) {
            stops = resolved
        } else {
            stops = stops + resolved.filter { r in !stops.contains { $0.stopId == r.stopId } }
        }
    }

    func refresh() async {
        let id = selectedStopId
        do {
            let arrivals = try await api.atacLive(stopIds: [id])[id] ?? []
            guard id == selectedStopId else { return }
            let now = Int(Date().timeIntervalSince1970) - 60
            live = arrivals.filter { $0.ts >= now }
            errorMessage = nil
            if live?.isEmpty == true, scheduledFor != id {
                scheduledFor = id
                isLoadingScheduled = true
                scheduled = (try? await api.atacSchedule(stopId: id)) ?? []
                isLoadingScheduled = false
            }
        } catch {
            guard !error.isCancellation, id == selectedStopId else { return }
            errorMessage = error.userMessage
        }
    }
}

struct AtacStopSheet: View {
    @StateObject private var model: AtacStopSheetModel
    @ObservedObject var favoritesStore: FavoritesStore

    init(group: AtacStopGroup, favoritesStore: FavoritesStore) {
        _model = StateObject(wrappedValue: AtacStopSheetModel(group: group))
        self.favoritesStore = favoritesStore
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: model.stops[0].stopName,
                subtitle: "Atac / Roma TPL · tempo reale",
                isFavorite: favoritesStore.isFavorite(atacStopId: model.selected.stopId),
                toggleFavorite: { favoritesStore.toggle(model.selected) }
            )
            if model.stops.count > 1 {
                platformPicker
            }
            if let error = model.errorMessage, model.live != nil, !(model.live?.isEmpty ?? true) {
                StaleDataStrip(message: error, retry: model.retry)
            }
            Divider()
            MinuteTicker { now in content(now: now) }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// Segmented for a typical two-platform stop; a menu for big stations
    /// (Termini has more than ten), where segments would be unreadable.
    @ViewBuilder
    private var platformPicker: some View {
        let picker = Picker("Direzione", selection: $model.selectedStopId) {
            ForEach(model.stops) { stop in
                Text(Self.platformLabel(stop)).tag(stop.stopId)
            }
        }
        if model.stops.count <= 3 {
            picker
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
        } else {
            HStack {
                Text("Direzione").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                picker.pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    static func platformLabel(_ stop: AtacStop) -> String {
        stop.headsign.map { "verso \($0)" } ?? "Fermata \(stop.stopId)"
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if model.live == nil {
            if let error = model.errorMessage {
                ErrorStateView(message: error, retry: model.retry)
            } else {
                LoadingStateView(message: "Carico gli arrivi…")
            }
        } else if !model.liveArrivals.isEmpty {
            List(model.liveArrivals) { arrival in
                AtacArrivalRow(arrival: arrival, now: now, isScheduled: false)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        } else if model.isLoadingScheduled {
            LoadingStateView(message: "Cerco gli orari in programma…")
        } else if !model.scheduled.isEmpty {
            List {
                Label("Nessun mezzo in tempo reale al momento: questi sono orari stimati da programmazione.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                ForEach(model.scheduled) { arrival in
                    AtacArrivalRow(arrival: arrival, now: now, isScheduled: true)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        } else {
            EmptyStateView(
                systemImage: "clock.badge.questionmark",
                title: "Nessun transito in tempo reale",
                message: "Questa fermata potrebbe non avere corse attive in questo momento."
            )
            .frame(maxHeight: .infinity)
        }
    }
}

struct AtacArrivalRow: View {
    let arrival: AtacArrival
    let now: Date
    let isScheduled: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.timeLabel)
                    .font(.title3.bold().monospacedDigit())
                    .strikethrough(arrival.cancelled)
                Text(relative).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            VStack(spacing: 2) {
                Image(systemName: arrival.kind.sfSymbolName)
                Text(AtacMetroLine(routeShortName: arrival.routeLabel)?.friendlyName ?? arrival.routeLabel)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 2) {
                if let headsign = arrival.headsign {
                    Text("verso \(headsign)").font(.subheadline).lineLimit(1)
                }
                if arrival.cancelled {
                    Text("soppressa").font(.caption.weight(.semibold)).foregroundStyle(.red)
                } else if isScheduled {
                    Text("stimato").font(.caption).foregroundStyle(.secondary)
                } else if let delay = RelativeTime.delayLabel(seconds: arrival.delaySeconds) {
                    Text(delay.text).font(.caption).foregroundStyle(delay.isLate ? .red : .green)
                }
            }

            Spacer(minLength: 0)
            StatusDot(color: isScheduled ? .gray : .green, pulse: !isScheduled && !arrival.cancelled)
        }
        .opacity(arrival.cancelled ? 0.6 : 1)
        .padding(.vertical, 4)
    }

    private var relative: String {
        let minutes = arrival.minutesFromNow(now: now)
        if isScheduled { return "tra \(max(minutes, 0)) min" }
        return RelativeTime.label(minutes: minutes) ?? ""
    }
}

// MARK: - Atac vehicle (stop-by-stop timetable of its run)

@MainActor
final class AtacVehicleSheetModel: ObservableObject {
    @Published private(set) var trip: AtacTripResponse?
    @Published private(set) var isLoaded = false
    @Published private(set) var errorMessage: String?

    let vehicle: TransitVehicle
    private let api: MadovaiAPI
    private lazy var poller = Poller(interval: 18) { [weak self] in await self?.refresh() }

    init(vehicle: TransitVehicle, api: MadovaiAPI = .shared) {
        self.vehicle = vehicle
        self.api = api
    }

    func start() { poller.start() }
    func stop() { poller.stop() }
    func retry() { errorMessage = nil; poller.refreshNow() }

    func refresh() async {
        guard let tripId = vehicle.tripId else {
            isLoaded = true
            return
        }
        do {
            trip = try await api.atacTrip(tripId: tripId)
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.userMessage
        }
        isLoaded = true
    }
}

struct AtacVehicleSheet: View {
    @StateObject private var model: AtacVehicleSheetModel
    @ObservedObject var fleet: AtacFleetService

    init(vehicle: TransitVehicle, fleet: AtacFleetService) {
        _model = StateObject(wrappedValue: AtacVehicleSheetModel(vehicle: vehicle))
        self.fleet = fleet
    }

    /// Re-resolved each refresh rather than freezing the tapped snapshot.
    private var live: TransitVehicle { fleet.vehicle(id: model.vehicle.id) ?? model.vehicle }

    var body: some View {
        let headsign = model.trip?.headsign.nonEmpty ?? live.headsign
        VStack(spacing: 0) {
            SheetHeader(
                title: headsign.map { "Linea \(live.lineName) verso \($0)" } ?? "Linea \(live.lineName)",
                subtitle: "\(live.transitOperator.rawValue) · tempo reale",
                systemImage: live.kind.sfSymbolName
            )
            if let error = model.errorMessage, !(model.trip?.stops.isEmpty ?? true) {
                StaleDataStrip(message: error, retry: model.retry)
            }
            Divider()
            MinuteTicker { now in content(now: now) }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let stops = model.trip?.stops ?? []
        if !model.isLoaded {
            LoadingStateView(message: "Carico l'orario della corsa…")
        } else if stops.isEmpty {
            if let error = model.errorMessage {
                ErrorStateView(message: error, retry: model.retry)
            } else {
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "Orario non disponibile",
                    message: "Non ho ancora un aggiornamento in tempo reale per questa corsa."
                )
                .frame(maxHeight: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                List(stops) { stop in
                    TripStopRow(stop: stop, isPast: stop.date < now)
                        .listRowSeparator(.hidden)
                        .id(stop.id)
                }
                .listStyle(.plain)
                .onAppear {
                    // Start at the next stop rather than the run's first one.
                    if let next = stops.first(where: { $0.date >= now }) {
                        proxy.scrollTo(next.id, anchor: .top)
                    }
                }
            }
        }
    }
}

private struct TripStopRow: View {
    let stop: AtacTripResponse.Stop
    let isPast: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.stopName).font(.subheadline.weight(.semibold))
                if let delay = RelativeTime.delayLabel(seconds: stop.delaySeconds) {
                    Text(delay.text).font(.caption).foregroundStyle(delay.isLate ? .red : .green)
                }
            }
            Spacer()
            Text(RomeTime.hhmm(unix: stop.ts))
                .font(.subheadline.monospacedDigit())
        }
        .opacity(isPast ? 0.45 : 1)
        .padding(.vertical, 2)
    }
}

// MARK: - Cotral vehicle (line timetable from ASTRAL)

@MainActor
final class CotralVehicleSheetModel: ObservableObject {
    enum Phase { case idle, loading, loaded, failed }

    @Published private(set) var stations: [AstralLineResponse.Station] = []
    @Published private(set) var phase: Phase
    @Published private(set) var errorMessage: String?

    let vehicle: TransitVehicle
    let trainRoute: CotralTrainRoute?
    private let api: MadovaiAPI
    private lazy var poller = Poller(interval: 30) { [weak self] in await self?.refresh() }

    init(vehicle: TransitVehicle, api: MadovaiAPI = .shared) {
        self.vehicle = vehicle
        self.trainRoute = vehicle.routeId.flatMap(CotralTrainRoute.init(rawValue:))
        self.api = api
        self.phase = trainRoute == nil ? .idle : .loading
    }

    func start() { if trainRoute != nil { poller.start() } }
    func stop() { poller.stop() }
    func retry() { errorMessage = nil; poller.refreshNow() }

    func refresh() async {
        guard let trainRoute else { return }
        do {
            let response = try await api.astralLine(route: trainRoute.rawValue)
            // "What's coming next anywhere on the line": by each station's
            // next passage, stations with nothing left today at the bottom.
            stations = response.stations.sorted { ($0.next?.sortSeconds ?? .max) < ($1.next?.sortSeconds ?? .max) }
            phase = .loaded
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.userMessage
            if phase != .loaded { phase = .failed }
        }
    }
}

struct CotralVehicleSheet: View {
    @StateObject private var model: CotralVehicleSheetModel

    init(vehicle: TransitVehicle) {
        _model = StateObject(wrappedValue: CotralVehicleSheetModel(vehicle: vehicle))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                SheetHeader(
                    title: "Linea \(model.vehicle.lineName)",
                    subtitle: "Cotral · posizione in tempo reale",
                    systemImage: model.vehicle.kind == .treno ? "tram.fill" : "bus"
                )
                if let delay = RelativeTime.delayLabel(seconds: model.vehicle.delaySeconds) {
                    Text(delay.text)
                        .font(.caption)
                        .foregroundStyle(delay.isLate ? .red : .green)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            if let error = model.errorMessage, model.phase == .loaded {
                StaleDataStrip(message: error, retry: model.retry)
            }
            Divider()
            content
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            EmptyStateView(
                systemImage: "info.circle",
                title: "Itinerario non disponibile",
                message: "Per i bus Cotral l'itinerario completo della corsa non è disponibile: tocca una palina per vedere i passaggi."
            )
            .frame(maxHeight: .infinity)
        case .loading:
            LoadingStateView(message: "Carico l'orario della linea…")
        case .failed:
            ErrorStateView(message: model.errorMessage ?? APIError.offline.message, retry: model.retry)
        case .loaded:
            if model.stations.isEmpty {
                EmptyStateView(
                    systemImage: "moon.zzz",
                    title: "Nessuna corsa in programma",
                    message: "Non risultano corse programmate per questa linea per il resto di oggi."
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Orario della linea, non di questa specifica corsa", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let route = model.trainRoute {
                            Text(route.directionLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .listRowSeparator(.hidden)
                    ForEach(model.stations) { station in
                        StationNextRow(station: station)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct StationNextRow: View {
    let station: AstralLineResponse.Station

    var body: some View {
        HStack(alignment: .top) {
            Text(station.name).font(.subheadline)
            Spacer()
            if let next = station.next {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        if next.isReplacementBus { Image(systemName: "bus").foregroundStyle(.secondary) }
                        Text(next.time).font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    if next.isCancelled {
                        CapsuleTag(text: "Soppressa", color: .red)
                    } else if let delay = RelativeTime.trainDelayLabel(minutes: next.delayMinutes) {
                        Text(delay.text.prefix(1).lowercased() + delay.text.dropFirst())
                            .font(.caption)
                            .foregroundStyle(delay.tone.color)
                    }
                }
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
