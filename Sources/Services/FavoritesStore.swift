import Foundation

/// Favorite poles, purely local (UserDefaults) — there's no server to share
/// them across a user's devices, which is fine for this app: each friend's
/// favorites are personal to their own phone.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favoritePoles: [Pole] = []
    @Published private(set) var favoritePoleCodes: Set<String> = []

    private static let storageKey = "dev.gab8bit.madovai.favoritePoles"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isFavorite(_ poleCode: String) -> Bool {
        favoritePoleCodes.contains(poleCode)
    }

    func toggle(_ pole: Pole) {
        guard let poleCode = pole.codicePalina else { return }
        if favoritePoleCodes.contains(poleCode) {
            favoritePoleCodes.remove(poleCode)
            favoritePoles.removeAll { $0.codicePalina == poleCode }
        } else {
            favoritePoleCodes.insert(poleCode)
            favoritePoles.append(pole)
        }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Pole].self, from: data)
        else { return }
        favoritePoles = decoded
        favoritePoleCodes = Set(decoded.compactMap(\.codicePalina))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favoritePoles) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
