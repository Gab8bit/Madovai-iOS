import SwiftUI

/// Standalone line browser, no map — pick a line, see its live vehicles and
/// stops. Limited to lines where that's actually meaningful: Atac/Roma TPL
/// (full live fleet + stop predictions) and Cotral's rail lines (tapping a
/// station opens the same schedule view as tapping its pole on the map —
/// ASTRAL's live schedule, falling back to static GTFS; see
/// `PoleDetailViewModel.scheduledDeparturesByDirection`). Cotral's ~4000 bus
/// routes are deliberately left out: with no per-line live data for them,
/// a list that size wouldn't be very browsable and would dominate the screen.
struct LineeListView: View {
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    @ObservedObject var atacRealtimeService: AtacRealtimeService
    let gtfsStore: GTFSStore
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker
    let transitsRepository: TransitsRepository
    let astralTrainRepository: AstralTrainRepository

    @State private var query = ""

    private var trainRoutes: [SearchRouteResult] {
        let atacTrains = atacGtfsStore.allRoutes()
            .filter { $0.kind == .metro }
            .map(SearchRouteResult.atac)
        let cotralTrains = gtfsStore.allRailRoutes().map(SearchRouteResult.cotral)
        return filtered(atacTrains + cotralTrains)
    }

    private var busRoutes: [SearchRouteResult] {
        filtered(atacGtfsStore.allRoutes().filter { $0.kind == .bus || $0.kind == .tram }.map(SearchRouteResult.atac))
    }

    private func filtered(_ routes: [SearchRouteResult]) -> [SearchRouteResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return routes.sorted { $0.shortName < $1.shortName } }
        return routes
            .filter { $0.shortName.lowercased().contains(q) || $0.longName.lowercased().contains(q) }
            .sorted { $0.shortName < $1.shortName }
    }

    var body: some View {
        NavigationView {
            List {
                if !trainRoutes.isEmpty {
                    Section("Treni") {
                        ForEach(trainRoutes) { route in
                            NavigationLink {
                                lineeDetail(for: route)
                            } label: {
                                LineRow(route: route)
                            }
                        }
                    }
                }
                if !busRoutes.isEmpty {
                    Section("Bus") {
                        ForEach(busRoutes) { route in
                            NavigationLink {
                                lineeDetail(for: route)
                            } label: {
                                LineRow(route: route)
                            }
                        }
                    }
                }
                if trainRoutes.isEmpty && busRoutes.isEmpty {
                    Text(atacGtfsStore.state == .ready ? "Nessuna linea trovata." : "Carico le linee…")
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "Cerca una linea")
            .navigationTitle("Linee")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func lineeDetail(for route: SearchRouteResult) -> some View {
        LineeDetailView(
            route: route,
            atacGtfsStore: atacGtfsStore,
            atacRealtimeService: atacRealtimeService,
            gtfsStore: gtfsStore,
            favoritesStore: favoritesStore,
            vehicleTracker: vehicleTracker,
            transitsRepository: transitsRepository,
            astralTrainRepository: astralTrainRepository
        )
    }
}

private struct LineRow: View {
    let route: SearchRouteResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.iconName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.displayName).font(.subheadline.weight(.semibold))
                if !route.longName.isEmpty {
                    Text(route.longName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(route.subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
