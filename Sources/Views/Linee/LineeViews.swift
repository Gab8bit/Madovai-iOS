import SwiftUI

/// Line browser without a map: Atac / Roma TPL lines (live fleet + stop
/// predictions) and Cotral's rail lines. Cotral's ~4000 bus routes are left
/// out on purpose (no per-line live data; a list that size isn't browsable).
struct LineeListView: View {
    @ObservedObject var linesStore: LinesStore
    let env: AppEnvironment

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if let lines = linesStore.lines {
                    let trains = filtered(lines.atac.filter { $0.kind == .metro } + lines.cotralRail)
                    let buses = filtered(lines.atac.filter { $0.kind == .bus || $0.kind == .tram })
                    if !trains.isEmpty {
                        Section("Treni e metro") {
                            ForEach(trains) { route in
                                NavigationLink(value: route) { LineRow(route: route) }
                            }
                        }
                    }
                    if !buses.isEmpty {
                        Section("Bus e tram") {
                            ForEach(buses) { route in
                                NavigationLink(value: route) { LineRow(route: route) }
                            }
                        }
                    }
                    if trains.isEmpty && buses.isEmpty {
                        Text("Nessuna linea trovata.").foregroundStyle(.secondary)
                    }
                } else if let error = linesStore.errorMessage {
                    ErrorStateView(message: error, retry: linesStore.retry)
                        .listRowBackground(Color.clear)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Carico le linee…").foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Cerca una linea")
            .refreshable { await linesStore.load() }
            .navigationTitle("Linee")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RouteInfo.self) { route in
                LineDetailView(route: route, env: env)
            }
        }
        .task { await linesStore.load() }
    }

    private func filtered(_ routes: [RouteInfo]) -> [RouteInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return routes
            .filter { q.isEmpty || $0.shortName.lowercased().contains(q) || $0.displayName.lowercased().contains(q) || $0.longName.lowercased().contains(q) }
            .sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }
    }
}

private struct LineRow: View {
    let route: RouteInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.iconName)
                .foregroundStyle(route.colorHex.flatMap { UIColor(hex: $0) }.map(Color.init) ?? Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.title)
                    .font(.subheadline.weight(.semibold))
                if let sub = route.rail ? nil : route.subtitleName {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(route.operatorLabel).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Line detail, pushed from the Linee tab or shown in a sheet from search.
struct LineDetailView: View {
    let route: RouteInfo
    let env: AppEnvironment

    var body: some View {
        Group {
            if route.isAtac {
                AtacLineDetail(route: route, env: env, fleet: env.atacFleet)
            } else {
                CotralRailLineDetail(route: route, env: env)
            }
        }
        .navigationTitle(route.isMetro || route.rail ? route.title : "Linea \(route.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Fetch helper shared by both line details.
@MainActor
final class LineDetailModel: ObservableObject {
    @Published private(set) var detail: LineDetail?
    @Published private(set) var errorMessage: String?
    @Published private(set) var arrivals: [String: [AtacArrival]] = [:]

    let route: RouteInfo
    private let api: MadovaiAPI
    private lazy var arrivalsPoller = Poller(interval: 18) { [weak self] in await self?.refreshArrivals() }

    init(route: RouteInfo, api: MadovaiAPI = .shared) {
        self.route = route
        self.api = api
    }

    func load() async {
        guard detail == nil else { return }
        do {
            detail = try await api.line(source: route.source, id: route.routeId)
            errorMessage = nil
            if route.isAtac { arrivalsPoller.start() }
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.userMessage
        }
    }

    func retry() {
        errorMessage = nil
        Task { await load() }
    }

    func stopPolling() { arrivalsPoller.stop() }

    private func refreshArrivals() async {
        guard let stops = detail?.stops, !stops.isEmpty else { return }
        if let result = try? await api.atacLive(stopIds: stops.map(\.id)) {
            arrivals = result
        }
    }
}

private struct AtacLineDetail: View {
    let route: RouteInfo
    let env: AppEnvironment
    @ObservedObject var fleet: AtacFleetService
    @StateObject private var model: LineDetailModel
    @State private var selectedStation: AtacStopGroup?

    init(route: RouteInfo, env: AppEnvironment, fleet: AtacFleetService) {
        self.route = route
        self.env = env
        self.fleet = fleet
        _model = StateObject(wrappedValue: LineDetailModel(route: route))
    }

    private var vehicles: [TransitVehicle] { fleet.vehicles.filter { $0.routeId == route.routeId } }

    var body: some View {
        let groups = groupedStopsByName((model.detail?.stops ?? []).map(\.asAtacStop))
        MinuteTicker { now in
            List {
                Section("Veicoli in tempo reale (\(vehicles.count))") {
                    if vehicles.isEmpty {
                        Text(fleet.hasLoadedOnce ? "Nessun veicolo attivo al momento su questa linea." : "Carico i veicoli…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vehicles) { vehicle in
                            HStack {
                                Image(systemName: vehicle.kind.sfSymbolName).foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Veicolo \(vehicle.id.replacingOccurrences(of: "atac-", with: ""))").font(.subheadline)
                                    if let headsign = vehicle.headsign {
                                        Text("verso \(headsign)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                StatusDot(color: .green, pulse: true)
                            }
                        }
                    }
                }

                Section("Fermate (\(groups.count))") {
                    if let error = model.errorMessage {
                        ErrorStateView(message: error, retry: model.retry)
                    } else if model.detail == nil {
                        HStack(spacing: 10) { ProgressView(); Text("Carico le fermate…").foregroundStyle(.secondary) }
                    } else if groups.isEmpty {
                        Text("Nessuna fermata trovata per questa linea.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(groups) { group in
                            Button {
                                selectedStation = AtacStopGroup(name: group.name, stops: group.stops, routeId: route.routeId)
                            } label: {
                                stationRow(group, now: now)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .task { await model.load() }
        .onDisappear { model.stopPolling() }
        .sheet(item: $selectedStation) { group in
            AtacStopSheet(group: group, favoritesStore: env.favoritesStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func stationRow(_ group: AtacStopGroup, now: Date) -> some View {
        let next = group.stops
            .flatMap { model.arrivals[$0.stopId] ?? [] }
            .filter { $0.routeId == route.routeId && $0.date >= now.addingTimeInterval(-60) }
            .min { $0.ts < $1.ts }
        let directions = group.stops.count > 1 ? group.stops.compactMap(\.headsign) : []
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(.subheadline)
                if !directions.isEmpty {
                    Text(directions.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let next {
                let minutes = next.minutesFromNow(now: now)
                Text(minutes <= 0 ? "in arrivo" : "\(minutes) min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Cotral line (rail from Linee, rail or bus from search): stops in line
/// order, each opening the same sheet as its pole on the map.
private struct CotralRailLineDetail: View {
    let route: RouteInfo
    let env: AppEnvironment
    @StateObject private var model: LineDetailModel
    @State private var selectedPole: Pole?

    init(route: RouteInfo, env: AppEnvironment) {
        self.route = route
        self.env = env
        _model = StateObject(wrappedValue: LineDetailModel(route: route))
    }

    var body: some View {
        let stops = dedupedByName(model.detail?.stops ?? [])
        List {
            Section {
                Label(route.rail
                      ? "Gli orari di ogni stazione seguono Cotral in tempo reale quando disponibile, altrimenti un orario programmato — tocca una stazione per vederli."
                      : "Tocca una fermata per vedere i prossimi passaggi, in tempo reale quando la corsa è monitorata.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("\(route.rail ? "Stazioni" : "Fermate") (\(stops.count))") {
                if let error = model.errorMessage {
                    ErrorStateView(message: error, retry: model.retry)
                } else if model.detail == nil {
                    HStack(spacing: 10) { ProgressView(); Text(route.rail ? "Carico le stazioni…" : "Carico le fermate…").foregroundStyle(.secondary) }
                } else {
                    ForEach(stops, id: \.id) { stop in
                        Button {
                            selectedPole = Pole(cotralId: stop.id, name: stop.name, locality: nil, lat: stop.lat, lon: stop.lon, rail: route.rail)
                        } label: {
                            HStack {
                                Text(stop.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task { await model.load() }
        .sheet(item: $selectedPole) { pole in
            PoleSheet(pole: pole, favoritesStore: env.favoritesStore, tracker: env.vehicleTracker)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// A station is often several GTFS stops (one per platform): one row per name.
    private func dedupedByName(_ stops: [LineStopDTO]) -> [LineStopDTO] {
        var seen = Set<String>()
        return stops.filter { seen.insert($0.name.trimmingCharacters(in: .whitespaces).lowercased()).inserted }
    }
}

/// A Cotral line picked from the map's search bar, as a sheet.
struct LineSheet: View {
    let route: RouteInfo
    let env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LineDetailView(route: route, env: env)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { dismiss() }
                    }
                }
        }
    }
}
