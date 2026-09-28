import SwiftUI

/// Self-contained "Preferiti" tab — a unified list of both Cotral poles and
/// Atac/Roma TPL stops (`FavoriteStop`), each opening the exact same detail
/// sheet tapping it on the map or in "Linee" would, so there's only one
/// schedule view per stop kind to keep in sync.
struct FavoritesListView: View {
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    @ObservedObject var atacRealtimeService: AtacRealtimeService
    let gtfsStore: GTFSStore
    @ObservedObject var vehicleTracker: VehicleTracker
    let transitsRepository: TransitsRepository
    let astralTrainRepository: AstralTrainRepository

    @State private var selectedPole: Pole?
    @State private var selectedAtacStopGroup: AtacStopGroup?

    var body: some View {
        NavigationView {
            Group {
                if favoritesStore.favorites.isEmpty {
                    EmptyStateView(
                        systemImage: "star",
                        title: "Nessun preferito",
                        message: "Tocca la stella su una fermata o palina per salvarla qui."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(favoritesStore.favorites) { item in
                        Button {
                            select(item)
                        } label: {
                            HStack {
                                Image(systemName: icon(for: item))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                        .foregroundStyle(.primary)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
            .navigationTitle("Preferiti")
            .navigationBarTitleDisplayMode(.inline)
        }
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
        .sheet(item: $selectedAtacStopGroup) { group in
            AtacStopDetailSheet(
                stops: group.stops,
                routeId: nil,
                realtimeService: atacRealtimeService,
                atacGtfsStore: atacGtfsStore,
                favoritesStore: favoritesStore
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func select(_ item: FavoriteStop) {
        switch item {
        case .cotral(let pole):
            selectedPole = pole
        case .atac(let stop):
            // Resolves back to every platform sharing this stop's name (not
            // just the one favorited), same as a bare map-pin tap — see
            // `ContentView.selectAtacStopGroup(containing:)`'s doc comment.
            let stops = atacGtfsStore.stopsSharingName(with: stop)
            selectedAtacStopGroup = AtacStopGroup(name: stop.stopName.trimmingCharacters(in: .whitespaces), stops: stops)
        }
    }

    private func icon(for item: FavoriteStop) -> String {
        switch item {
        case .cotral(let pole): return pole.isTreno ? "tram.fill" : "bus"
        case .atac: return "location.fill"
        }
    }
}
