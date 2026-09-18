import SwiftUI

struct LineeDetailView: View {
    let route: SearchRouteResult
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    @ObservedObject var atacRealtimeService: AtacRealtimeService
    let gtfsStore: GTFSStore
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker
    let transitsRepository: TransitsRepository
    let cotralTrainScheduleRepository: CotralTrainScheduleRepository

    var body: some View {
        Group {
            switch route {
            case .atac(let atacRoute):
                AtacLineDetail(route: atacRoute, atacGtfsStore: atacGtfsStore, atacRealtimeService: atacRealtimeService)
            case .cotral(let gtfsRoute):
                CotralRailLineDetail(
                    route: gtfsRoute,
                    gtfsStore: gtfsStore,
                    favoritesStore: favoritesStore,
                    vehicleTracker: vehicleTracker,
                    transitsRepository: transitsRepository,
                    cotralTrainScheduleRepository: cotralTrainScheduleRepository
                )
            }
        }
        .navigationTitle(route.shortName)
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
/// always realtime; a tapped stop's own detail sheet additionally falls
/// back to a static-timetable estimate when it has no live prediction at
/// all (see `AtacGtfsStore.scheduledDepartures(forStopId:)`).
private struct AtacLineDetail: View {
    let route: AtacRoute
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    @ObservedObject var atacRealtimeService: AtacRealtimeService
    @State private var selectedStop: AtacStop?

    private var vehicles: [TransitVehicle] {
        atacRealtimeService.vehicles.filter { $0.routeId == route.routeId }
    }

    private var stops: [AtacStop] {
        dedupedByName(atacGtfsStore.stopsForRoute(route.routeId), name: \.stopName)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: route.kind.sfSymbolName)
                    Text(route.routeLongName.isEmpty ? route.routeShortName : route.routeLongName)
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
                            Text("Veicolo \(vehicle.id.replacingOccurrences(of: "atac-", with: ""))")
                                .font(.subheadline)
                            Spacer()
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                        }
                    }
                }
            }

            Section("Fermate (\(stops.count))") {
                if stops.isEmpty {
                    Text("Nessuna fermata trovata per questa linea nel riquadro considerato.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stops, id: \.stopId) { stop in
                        Button {
                            selectedStop = stop
                        } label: {
                            StopPredictionRow(stop: stop, routeId: route.routeId, realtimeService: atacRealtimeService)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedStop) { stop in
            AtacStopDetailSheet(stop: stop, realtimeService: atacRealtimeService, atacGtfsStore: atacGtfsStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct StopPredictionRow: View {
    let stop: AtacStop
    let routeId: String
    @ObservedObject var realtimeService: AtacRealtimeService

    private var nextArrival: AtacStopPrediction? {
        (realtimeService.stopPredictions[stop.stopId] ?? []).first { $0.routeId == routeId }
    }

    var body: some View {
        HStack {
            Text(stop.stopName).font(.subheadline)
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
/// (`PoleDetailSheetContainer`) — live PIV.do transits when Cotral has them
/// for that stop, the cotralspa.it widget or the static GTFS timetable
/// otherwise (see `PoleDetailViewModel.scheduledDeparturesByDirection`).
private struct CotralRailLineDetail: View {
    let route: GtfsRoute
    let gtfsStore: GTFSStore
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker
    let transitsRepository: TransitsRepository
    let cotralTrainScheduleRepository: CotralTrainScheduleRepository

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
                cotralTrainScheduleRepository: cotralTrainScheduleRepository
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
