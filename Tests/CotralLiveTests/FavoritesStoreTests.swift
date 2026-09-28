import XCTest
@testable import CotralLive

/// Covers the migration/dedup logic added after a real bug: the same
/// station could get favorited twice under two different `codicePalina`
/// values (see `PoleDetailViewModel.mergedPole`'s doc comment), and the
/// pre-Atac-favorites persisted format was a bare `[Pole]` array that must
/// keep loading correctly after `FavoritesStore` moved to `[FavoriteStop]`.
@MainActor
final class FavoritesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let storageKey = "dev.gab8bit.madovai.favoritePoles"
    // A plain identifier, not `#file` — that's an absolute path, and
    // `UserDefaults(suiteName:)` happily writes a real `<path>.plist`
    // straight into the project tree for a path-shaped suite name instead
    // of treating it as an opaque domain, leaving a stray binary plist
    // behind next to this very test file.
    private let suiteName = "dev.gab8bit.madovai.FavoritesStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func pole(_ code: String) -> Pole {
        Pole(codicePalina: code, nomePalina: "Palina \(code)")
    }

    private func atacStop(_ id: String) -> AtacStop {
        AtacStop(stopId: id, stopName: "Fermata \(id)", lat: 41.9, lon: 12.5)
    }

    func testMigratesLegacyBarePoleArrayFormat() {
        let legacy = [pole("A1"), pole("A2")]
        defaults.set(try! JSONEncoder().encode(legacy), forKey: storageKey)

        let store = FavoritesStore(defaults: defaults)

        XCTAssertEqual(store.favorites.count, 2)
        XCTAssertTrue(store.isFavorite("A1"))
        XCTAssertTrue(store.isFavorite("A2"))
    }

    func testDedupesDuplicateFavoritesFromBeforeTheFix() {
        // Two entries sharing one `codicePalina` — what a pre-fix
        // `mergedPole` overwrite could produce once toggled at two
        // different moments in a pole's live-refresh lifecycle.
        let stored: [FavoriteStop] = [.cotral(pole("SAME")), .cotral(pole("SAME"))]
        defaults.set(try! JSONEncoder().encode(stored), forKey: storageKey)

        let store = FavoritesStore(defaults: defaults)

        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertTrue(store.isFavorite("SAME"))
    }

    func testCotralAndAtacFavoritesWithTheSameBareIdDontCollide() {
        let store = FavoritesStore(defaults: defaults)
        let sharedId = "12345"

        store.toggle(pole(sharedId))
        store.toggle(atacStop(sharedId))

        XCTAssertEqual(store.favorites.count, 2)
        XCTAssertTrue(store.isFavorite(sharedId))
        XCTAssertTrue(store.isFavorite(atacStopId: sharedId))
    }

    func testTogglingSameStopTwiceRemovesIt() {
        let store = FavoritesStore(defaults: defaults)
        let target = pole("REMOVE-ME")

        store.toggle(target)
        XCTAssertTrue(store.isFavorite("REMOVE-ME"))

        store.toggle(target)
        XCTAssertFalse(store.isFavorite("REMOVE-ME"))
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func testPoleWithoutCodeIsIgnored() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle(Pole(nomePalina: "No code"))
        XCTAssertTrue(store.favorites.isEmpty)
    }
}
