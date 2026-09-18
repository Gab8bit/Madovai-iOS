import SwiftUI

struct FavoritesListView: View {
    @ObservedObject var favoritesStore: FavoritesStore
    var onSelect: (Pole) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if favoritesStore.favoritePoles.isEmpty {
                    EmptyStateView(
                        systemImage: "star",
                        title: "Nessuna palina preferita",
                        message: "Tocca la stella su una palina per salvarla qui."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(favoritesStore.favoritePoles) { pole in
                        Button {
                            onSelect(pole)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pole.displayName)
                                    .foregroundStyle(.primary)
                                if let subtitle = pole.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Preferiti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
