import SwiftUI

struct LineeDetailView: View {
    let route: SearchRouteResult
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    @ObservedObject var atacRealtimeService: AtacRealtimeService
    let gtfsStore: GTFSStore
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker
    let transitsRepository: TransitsRepository
    let astralTrainRepository: AstralTrainRepository

    var body: some View {
        Group {
            switch route {
            case .atac(let atacRoute):
                AtacLineDetail(route: atacRoute, atacGtfsStore: atacGtfsStore, atacRealtimeService: atacRealtimeService, favoritesStore: favoritesStore)
            case .cotral(let gtfsRoute):
                CotralRailLineDetail(
                    route: gtfsRoute,
                    gtfsStore: gtfsStore,
                    favoritesStore: favoritesStore,
                    vehicleTracker: vehicleTracker,
                    transitsRepository: transitsRepository,
                    astralTrainRepository: astralTrainRepository
                )
            }
        }
        .navigationTitle(route.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A real physical station is frequently split across several GTFS
/// `stop_id` records (different platforms/directions) — exact route<->stop
/// membership (`stopsForRoute`) correctly returns all of them for map
/// rendering (each is a real, distinctly-located marker there), but a flat
/// text list has no way to show that distinction, so it just reads as the
/// same name repeated. Keeping the first (already-sorted) record per name
/// collapses that for display without touching the underlying data other
/// callers rely on.
private func dedupedByName<Stop>(_ stops: [Stop], name: (Stop) -> String) -> [Stop] {
    var seen = Set<String>()
    var result: [Stop] = []
    for stop in stops {
        let key = name(stop).trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        result.append(stop)
    }
    return result
}

/// Atac/Roma TPL: live vehicles + per-stop predictions. Vehicles here are
/// always realtime; a tapped station's own detail sheet additionally falls
/// back to a static-timetable estimate when it has no live prediction at
/// all (see `AtacGtfsStore.scheduledDepartures(forStopId:)`). Stations are
/// grouped by name via the shared `groupedStopsByName` (also used by the
/// map's own pins/search, so a station reads as one place everywhere).
private struct AtacLineDetail: View {
    let route: AtacRoute
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    @ObservedObject var atacRealtimeService: AtacRealtimeService
    @ObservedObject var favoritesStore: FavoritesStore
    @State private var selectedStation: AtacStopGroup?

    private var vehicles: [TransitVehicle] {
        atacRealtimeService.vehicles.filter { $0.routeId == route.routeId }
    }

    private var stationGroups: [AtacStopGroup] {
        groupedStopsByName(atacGtfsStore.stopsForRoute(route.routeId))
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: route.kind.sfSymbolName)
                    Text(route.friendlyName)
                        .font(.subheadline)
                    Spacer()
                }
            }

            Section("Veicoli in tempo reale (\(vehicles.count))") {
                if vehicles.isEmpty {
                    Text("Nessun veicolo attivo al momento su questa linea.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vehicles) { vehicle in
                        HStack {
                            Image(systemName: vehicle.kind.sfSymbolName).foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Veicolo \(vehicle.id.replacingOccurrences(of: "atac-", with: ""))")
                                    .font(.subheadline)
                                if let headsign = vehicle.tripId.flatMap({ atacGtfsStore.headsign(forTripId: $0) }) {
                                    Text("verso \(headsign)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                        }
                    }
                }
            }

            Section("Fermate (\(stationGroups.count))") {
                if stationGroups.isEmpty {
                    Text("Nessuna fermata trovata per questa linea nel riquadro considerato.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stationGroups) { station in
                        Button {
                            selectedStation = station
                        } label: {
                            StopPredictionRow(station: station, routeId: route.routeId, atacGtfsStore: atacGtfsStore, realtimeService: atacRealtimeService)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedStation) { station in
            AtacStopDetailSheet(
                stops: station.stops,
                routeId: route.routeId,
                realtimeService: atacRealtimeService,
                atacGtfsStore: atacGtfsStore,
                favoritesStore: favoritesStore
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct StopPredictionRow: View {
    let station: AtacStopGroup
    let routeId: String
    let atacGtfsStore: AtacGtfsStore
    @ObservedObject var realtimeService: AtacRealtimeService

    /// Soonest prediction across every platform of this station for this
    /// route — either direction could be the one arriving next.
    private var nextArrival: AtacStopPrediction? {
        station.stops
            .flatMap { realtimeService.stopPredictions[$0.stopId] ?? [] }
            .filter { $0.routeId == routeId }
            .min { $0.arrival < $1.arrival }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.subheadline)
                if station.stops.count > 1 {
                    let directions = station.stops.compactMap { atacGtfsStore.headsign(forRouteId: routeId, stopId: $0.stopId) }
                    if !directions.isEmpty {
                        Text(directions.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            if let prediction = nextArrival {
                Text(prediction.minutesFromNow <= 0 ? "in arrivo" : "\(prediction.minutesFromNow) min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Cotral rail (Roma Lido/Metromare, Roma-Viterbo, ecc.): tapping a station
/// opens the exact same schedule view as tapping its pole on the map
/// (`PoleDetailSheetContainer`) — ASTRAL's schedule (real delay,
/// cancellations) when it resolves this station, the static GTFS timetable
/// otherwise (see `PoleDetailViewModel.scheduledDeparturesByDirection`).
private struct CotralRailLineDetail: View {
    let route: GtfsRoute
    let gtfsStore: GTFSStore
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker
    let transitsRepository: TransitsRepository
    let astralTrainRepository: AstralTrainRepository

    @State private var selectedPole: Pole?

    private var stops: [GtfsStop] {
        dedupedByName(gtfsStore.stopsForRouteInOrder(route.routeId), name: \.stopName)
    }

    private var polesRepository: PolesRepository { PolesRepository(gtfsStore: gtfsStore) }

    var body: some View {
        List {
            Section {
                Label("Gli orari di ogni stazione seguono Cotral in tempo reale quando disponibile, altrimenti un orario programmato — tocca una stazione per vederli.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Stazioni (\(stops.count))") {
                ForEach(stops, id: \.stopId) { stop in
                    Button {
                        selectedPole = polesRepository.pole(for: stop)
                    } label: {
                        HStack {
                            Text(stop.stopName).font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedPole) { pole in
            PoleDetailSheetContainer(
                pole: pole,
                favoritesStore: favoritesStore,
                vehicleTracker: vehicleTracker,
                transitsRepository: transitsRepository,
                gtfsStore: gtfsStore,
                astralTrainRepository: astralTrainRepository
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
