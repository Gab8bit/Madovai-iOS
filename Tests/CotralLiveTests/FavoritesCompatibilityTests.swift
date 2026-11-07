import XCTest
@testable import CotralLive

/// Favorites saved by 1.x must load unchanged in 2.0 (the stop models
/// gained fields; the persisted shape must stay compatible).
@MainActor
final class FavoritesCompatibilityTests: XCTestCase {
    private let suiteName = "dev.gab8bit.madovai.FavoritesCompatibilityTests"
    private let storageKey = "dev.gab8bit.madovai.favoritePoles"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadsFavoritesWrittenBy1x() {
        // The JSON 1.3.0 wrote for one Cotral pole and one Atac stop.
        let json = #"""
        [{"cotral":{"_0":{"codicePalina":"f3583","codiceStop":"f3583","nomePalina":"ROMA, Anagnina (Metro A)","nomeStop":"ROMA, Anagnina (Metro A)","localita":"ROMA","coordX":41.84,"coordY":12.58,"isTreno":false}}},
         {"atac":{"_0":{"stopId":"70240","stopName":"TERMINI (MA-MB-FS)","lat":41.901158,"lon":12.500047}}}]
        """#
        defaults.set(Data(json.utf8), forKey: storageKey)

        let store = FavoritesStore(defaults: defaults)

        XCTAssertEqual(store.favorites.count, 2)
        XCTAssertTrue(store.isFavorite("f3583"))
        XCTAssertTrue(store.isFavorite(atacStopId: "70240"))
        XCTAssertEqual(store.favoritePoleCodes, ["f3583"])
    }

    func testRemoveDeletesAndPersists() {
        let store = FavoritesStore(defaults: defaults)
        let stop = AtacStop(stopId: "1", stopName: "A", lat: 0, lon: 0, headsign: "Termini")
        store.toggle(stop)
        XCTAssertTrue(store.isFavorite(atacStopId: "1"))
        store.remove(.atac(stop))
        XCTAssertFalse(FavoritesStore(defaults: defaults).isFavorite(atacStopId: "1"))
    }

    func testPoleFromBackendStopMatchesOldFavoriteId() {
        // A favorite saved in 1.x used the GTFS stop id as `codicePalina`;
        // poles built from 2.0's API must produce the same id.
        let pole = Pole(cotralId: "f3583", name: "ROMA, Anagnina (Metro A)", locality: "ROMA", lat: 41.84, lon: 12.58, rail: false)
        XCTAssertEqual(pole.id, "f3583")
        XCTAssertEqual(FavoriteStop.cotral(pole).id, "cotral:f3583")
    }
}
