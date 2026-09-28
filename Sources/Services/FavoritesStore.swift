import Foundation

/// A favorited stop from either operator — Cotral's own `Pole` and Atac's
/// `AtacStop` are unrelated id spaces (same kind of gotcha this app already
/// works around for ASTRAL vs PIV.do codes elsewhere), so this keeps both
/// kinds in one persisted list without conflating their identities.
enum FavoriteStop: Codable, Identifiable, Hashable {
    case cotral(Pole)
    case atac(AtacStop)

    /// Namespaced so a Cotral and an Atac id that happen to collide as bare
    /// strings still can't be mistaken for the same favorite.
    var id: String {
        switch self {
        case .cotral(let pole): return "cotral:\(pole.id)"
        case .atac(let stop): return "atac:\(stop.stopId)"
        }
    }

    var displayName: String {
        switch self {
        case .cotral(let pole): return pole.displayName
        case .atac(let stop): return stop.stopName
        }
    }

    var subtitle: String? {
        switch self {
        case .cotral(let pole): return pole.subtitle
        case .atac: return "Atac / Roma TPL"
        }
    }
}

/// Favorite stops, purely local (UserDefaults) — there's no server to share
/// them across a user's devices, which is fine for this app: each friend's
/// favorites are personal to their own phone.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoriteStop] = []
    @Published private(set) var favoriteIds: Set<String> = []

    private static let storageKey = "dev.gab8bit.madovai.favoritePoles"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Bare Cotral pole codes only (no "cotral:" namespace prefix) — kept
    /// for the map's own pin-star styling (`MapContainerView`), which only
    /// ever deals with a Cotral `Pole.id` and predates Atac favorites.
    var favoritePoleCodes: Set<String> {
        Set(favorites.compactMap { item in
            if case .cotral(let pole) = item { return pole.id }
            return nil
        })
    }

    /// Cotral favorites only, in the shape older call sites (the map, the
    /// old favorites list) already expect.
    var favoritePoles: [Pole] {
        favorites.compactMap { item in
            if case .cotral(let pole) = item { return pole }
            return nil
        }
    }

    func isFavorite(_ poleCode: String) -> Bool {
        favoriteIds.contains("cotral:\(poleCode)")
    }

    func isFavorite(atacStopId stopId: String) -> Bool {
        favoriteIds.contains("atac:\(stopId)")
    }

    func toggle(_ pole: Pole) {
        guard pole.codicePalina != nil else { return }
        toggle(.cotral(pole))
    }

    func toggle(_ stop: AtacStop) {
        toggle(.atac(stop))
    }

    private func toggle(_ item: FavoriteStop) {
        if favoriteIds.contains(item.id) {
            favoriteIds.remove(item.id)
            favorites.removeAll { $0.id == item.id }
        } else {
            favoriteIds.insert(item.id)
            favorites.append(item)
        }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([FavoriteStop].self, from: data) {
            apply(decoded, resavingIfChanged: true)
            return
        }
        // Pre-Atac-favorites format: a bare `[Pole]` array. Migrated in
        // place rather than discarded, so this update doesn't look like it
        // wiped favorites again on top of the reinstall-driven wipe the
        // user already ran into once.
        if let legacyPoles = try? JSONDecoder().decode([Pole].self, from: data) {
            apply(legacyPoles.map(FavoriteStop.cotral), resavingIfChanged: true)
            persist()
        }
    }

    /// Self-heals favorites saved before a since-fixed bug let the same
    /// station get stored twice under two different `codicePalina` values
    /// (see `PoleDetailViewModel.mergedPole`'s doc comment) — keeps the
    /// first occurrence of each id, re-persisting once so this only has to
    /// run once per affected install.
    private func apply(_ items: [FavoriteStop], resavingIfChanged: Bool) {
        var seen = Set<String>()
        var deduped: [FavoriteStop] = []
        for item in items {
            guard seen.insert(item.id).inserted else { continue }
            deduped.append(item)
        }
        favorites = deduped
        favoriteIds = seen
        if resavingIfChanged, deduped.count != items.count { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
