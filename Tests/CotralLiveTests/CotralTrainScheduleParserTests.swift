import XCTest
@testable import CotralLive

/// Tests for the train-schedule HTML parser — the most fragile part of the
/// feature (see `CotralTrainScheduleParser`'s doc comment), so this is
/// tested against real captured markup (`TrainScheduleFixtures`), not
/// synthesized HTML that might be more forgiving than what the site
/// actually sends.
final class CotralTrainScheduleParserTests: XCTestCase {
    func testParsesStationsAndPassagesInOrder() {
        let stations = CotralTrainScheduleParser.parse(html: TrainScheduleFixtures.twoStationsHTML)

        XCTAssertEqual(stations.map(\.stationName), ["Cristoforo Colombo", "Castelfusano"])

        XCTAssertEqual(stations[0].passages.map(\.time), ["11:40", "12:00", "12:20", "12:40"])
        XCTAssertEqual(stations[0].passages.map(\.status), Array(repeating: "In orario", count: 4))

        XCTAssertEqual(stations[1].passages.map(\.time), ["11:42", "12:02", "12:22"])
        XCTAssertEqual(stations[1].passages.map(\.status), Array(repeating: "In orario", count: 3))
    }

    func testEmptyHTMLReturnsEmptyArray() {
        XCTAssertEqual(CotralTrainScheduleParser.parse(html: ""), [])
    }

    func testMarkupWithNoRecognizedStationsReturnsEmptyArray() {
        // Simulates the site's CSS class names changing entirely — the
        // parser should degrade to "no data" rather than crash or produce
        // garbage.
        let unrecognizable = "<div class=\"SomethingElseEntirely\"><p>11:40</p></div>"
        XCTAssertEqual(CotralTrainScheduleParser.parse(html: unrecognizable), [])
    }

    func testEmptyEndpointResultProducesNoStations() {
        // The endpoint's real shape for "no data" (invalid codicePercorso /
        // missing date) — HTTP 200, wrapper present, zero accordions.
        let html = CotralTrainScheduleEnvelope.extractHTML(from: TrainScheduleFixtures.emptyEnvelope)
        XCTAssertEqual(CotralTrainScheduleParser.parse(html: html), [])
    }
}

final class CotralTrainScheduleEnvelopeTests: XCTestCase {
    func testWellFormedJSONEnvelope() {
        let html = CotralTrainScheduleEnvelope.extractHTML(from: TrainScheduleFixtures.wellFormedEnvelope)
        let stations = CotralTrainScheduleParser.parse(html: html)
        XCTAssertEqual(stations.map(\.stationName), ["Cristoforo Colombo", "Castelfusano"])
    }

    func testMalformedControlCharacterEnvelopeStillParses() {
        // The exact malformation observed from the live endpoint: valid
        // JSON shape, but literal unescaped newlines/tabs inside the
        // "response" string break a strict JSON parser. Extraction must
        // fall back to a lenient unwrap and still recover the HTML.
        let html = CotralTrainScheduleEnvelope.extractHTML(from: TrainScheduleFixtures.malformedControlCharacterEnvelope)
        let stations = CotralTrainScheduleParser.parse(html: html)
        XCTAssertEqual(stations.map(\.stationName), ["Cristoforo Colombo", "Castelfusano"])
    }

    func testRawHTMLWithNoEnvelopeIsUsedAsIs() {
        // The other flakiness observed live: sometimes the endpoint skips
        // the JSON envelope entirely and just sends the HTML body.
        let html = CotralTrainScheduleEnvelope.extractHTML(from: TrainScheduleFixtures.twoStationsHTML)
        XCTAssertEqual(html, TrainScheduleFixtures.twoStationsHTML)
    }

    func testEmptyResultEnvelopeUnwrapsToEmptyWrapper() {
        let html = CotralTrainScheduleEnvelope.extractHTML(from: TrainScheduleFixtures.emptyEnvelope)
        XCTAssertTrue(html.contains("TrainsRealtimeStops"))
        XCTAssertFalse(html.contains("LocalityAccordion__text heading-h3"))
    }
}

final class CotralTrainRouteTests: XCTestCase {
    func testAllSixRouteCodesArePresent() {
        let codes = Set(CotralTrainRoute.allCases.map(\.rawValue))
        XCTAssertEqual(codes, ["RL_CC-PSP", "RL_PSP-CC", "RN_RMMON", "RN_MONRM", "RV_CATVIT", "RV_VITCAT"])
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
        XCTAssertEqual(
            Set(CotralTrainRoute.directions(forGTFSRouteShortName: "RVEXT") ?? []),
            [.viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano]
        )
        XCTAssertNil(CotralTrainRoute.directions(forGTFSRouteShortName: "017"))
    }
}
