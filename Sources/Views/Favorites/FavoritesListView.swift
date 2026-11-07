import SwiftUI

/// "Preferiti": Cotral poles and Atac / Roma TPL stops in one list, each
/// opening the same sheet as tapping it on the map.
struct FavoritesListView: View {
    @ObservedObject var favoritesStore: FavoritesStore
    let env: AppEnvironment

    @State private var selectedPole: Pole?
    @State private var selectedAtacGroup: AtacStopGroup?

    var body: some View {
        NavigationStack {
            Group {
                if favoritesStore.favorites.isEmpty {
                    EmptyStateView(
                        systemImage: "star",
                        title: "Nessun preferito",
                        message: "Tocca la stella su una fermata o palina per salvarla qui."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(favoritesStore.favorites) { item in
                            Button { select(item) } label: { row(item) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button("Rimuovi", role: .destructive) { favoritesStore.remove(item) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Preferiti")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedPole) { pole in
            PoleSheet(pole: pole, favoritesStore: favoritesStore, tracker: env.vehicleTracker)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAtacGroup) { group in
            AtacStopSheet(group: group, favoritesStore: favoritesStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func row(_ item: FavoriteStop) -> some View {
        HStack {
            Image(systemName: icon(for: item))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).foregroundStyle(.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func select(_ item: FavoriteStop) {
        switch item {
        case .cotral(let pole):
            selectedPole = pole
        case .atac(let stop):
            // The sheet completes the station's other platforms itself.
            selectedAtacGroup = AtacStopGroup(name: stop.stopName, stops: [stop])
        }
    }

    private func icon(for item: FavoriteStop) -> String {
        switch item {
        case .cotral(let pole): return pole.isTreno ? "tram.fill" : "bus"
        case .atac: return "mappin.circle"
        }
    }
}
