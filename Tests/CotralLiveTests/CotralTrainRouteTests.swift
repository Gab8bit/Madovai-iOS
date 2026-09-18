import XCTest
@testable import CotralLive

final class CotralTrainRouteTests: XCTestCase {
    func testAllEightRouteCodesArePresent() {
        let codes = Set(CotralTrainRoute.allCases.map(\.rawValue))
        XCTAssertEqual(codes, [
            "RL_CC-PSP", "RL_PSP-CC",
            "RN_RMMON", "RN_MONRM",
            "RV_CATVIT", "RV_VITCAT",
            "RV_MORCAT", "RV_CATMOR",
        ])
    }

    func testReversedIsInvolution() {
        for route in CotralTrainRoute.allCases {
            XCTAssertEqual(route.reversed.reversed, route)
            XCTAssertNotEqual(route.reversed, route)
            XCTAssertEqual(route.reversed.lineName, route.lineName)
        }
    }

    func testDirectionsForGTFSRouteShortName() {
        // Real values from the rail GTFS feed's routes.txt (route_short_name),
        // confirmed via curl — both Roma-Viterbo lines share the "RN_" GTFS
        // stop prefix, so this route-based lookup is what actually
        // disambiguates them (see `CotralTrainRoute.directions`'s doc comment).
        XCTAssertEqual(
            Set(CotralTrainRoute.directions(forGTFSRouteShortName: "ROMALIDO") ?? []),
            [.metromareColomboToPortaSanPaolo, .metromarePortaSanPaoloToColombo]
        )
        XCTAssertEqual(
            Set(CotralTrainRoute.directions(forGTFSRouteShortName: "RVURB") ?? []),
            [.viterboUrbanaFlaminioToMontebello, .viterboUrbanaMontebelloToFlaminio]
        )
        // RVEXT now covers two distinct direction pairs — the regular
        // Catalano<->Viterbo service and the Morlupo<->Catalano short-turn
        // (confirmed live via /api/fermate/RV_MORCAT) — callers resolve
        // which ones actually apply to a given station themselves.
        XCTAssertEqual(
            Set(CotralTrainRoute.directions(forGTFSRouteShortName: "RVEXT") ?? []),
            [.viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano, .morlupoToCatalano, .catalanoToMorlupo]
        )
        XCTAssertNil(CotralTrainRoute.directions(forGTFSRouteShortName: "017"))
    }
}
