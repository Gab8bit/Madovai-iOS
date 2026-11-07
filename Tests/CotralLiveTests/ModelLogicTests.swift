import CoreLocation
import XCTest
@testable import CotralLive

final class RomeTimeTests: XCTestCase {
    func testMinutesFromNowUsesRomeTime() {
        let now = romeDate(2026, 11, 7, 12, 0)
        XCTAssertEqual(RomeTime.minutesFromNow("12:15", now: now), 15)
        XCTAssertEqual(RomeTime.minutesFromNow("11:58", now: now), -2)
    }

    func testMinutesFromNowWrapsAroundMidnight() {
        XCTAssertEqual(RomeTime.minutesFromNow("00:10", now: romeDate(2026, 11, 7, 23, 55)), 15)
        XCTAssertEqual(RomeTime.minutesFromNow("23:50", now: romeDate(2026, 11, 8, 0, 5)), -15)
        // Cotral writes post-midnight runs as "25:10".
        XCTAssertEqual(RomeTime.minutesFromNow("25:10", now: romeDate(2026, 11, 8, 1, 0)), 10)
    }

    func testMinutesFromNowRejectsGarbage() {
        XCTAssertNil(RomeTime.minutesFromNow("", now: Date()))
        XCTAssertNil(RomeTime.minutesFromNow("12", now: Date()))
        XCTAssertNil(RomeTime.minutesFromNow("ab:cd", now: Date()))
    }

    func testAddingSecondsWrapsBothWays() {
        XCTAssertEqual(RomeTime.adding(seconds: 600, to: "23:55"), "00:05")
        XCTAssertEqual(RomeTime.adding(seconds: -600, to: "00:05"), "23:55")
        XCTAssertEqual(RomeTime.adding(seconds: 120, to: "17:31"), "17:33")
    }

    func testHHMMFromUnixIsRomeLocal() {
        // 2026-11-07 11:21:30 UTC = 12:21 in Rome (CET, UTC+1).
        XCTAssertEqual(RomeTime.hhmm(unix: 1794050490), "12:21")
    }

    func testDelayWording() {
        XCTAssertNil(RelativeTime.delayLabel(seconds: 59))
        XCTAssertNil(RelativeTime.delayLabel(seconds: nil))
        XCTAssertEqual(RelativeTime.delayLabel(seconds: 185)?.text, "in ritardo di 3 min")
        XCTAssertEqual(RelativeTime.delayLabel(seconds: -120)?.text, "in anticipo di 2 min")
        XCTAssertEqual(RelativeTime.trainDelayLabel(minutes: 0)?.text, "Puntuale")
        XCTAssertNil(RelativeTime.trainDelayLabel(minutes: nil), "an unknown delay must never read as on time")
        XCTAssertEqual(RelativeTime.label(minutes: 0), "in arrivo")
        XCTAssertEqual(RelativeTime.label(minutes: 1), "tra 1 min")
    }
}

final class TransitTests: XCTestCase {
    private func transit(_ time: String, ritardo: Int = 0, monitorata: String = "1", alive: Bool = true, soppressa: String = "N") -> Transit {
        Transit(idCorsa: UUID().uuidString, percorso: "017", orarioPartenzaCorsa: time, arrivoCorsa: "VELLETRI | Stazione (f1)",
                soppressa: soppressa, tempoTransito: time, ritardoSeconds: ritardo, vehicleCode: "B1", vehicleAlive: alive, monitorata: monitorata)
    }

    func testAdjustedTimeAppliesOnlyReliableDelaysOfAtLeastAMinute() {
        XCTAssertEqual(transit("17:31", ritardo: 120).adjustedDisplayTime, "17:33")
        XCTAssertEqual(transit("17:31", ritardo: -120).adjustedDisplayTime, "17:29")
        XCTAssertEqual(transit("17:31", ritardo: 30).adjustedDisplayTime, "17:31")
        XCTAssertEqual(transit("17:31", ritardo: 300, monitorata: "0").adjustedDisplayTime, "17:31")
        XCTAssertEqual(transit("17:31", ritardo: 300, alive: false).adjustedDisplayTime, "17:31")
    }

    func testOnlyYMeansCancelled() {
        XCTAssertTrue(transit("10:00", soppressa: " y ").isCancelled)
        XCTAssertFalse(transit("10:00", soppressa: "N").isCancelled)
        XCTAssertFalse(transit("10:00", soppressa: "S").isCancelled)
    }

    func testUpcomingSortedDropsStaleRunsButKeepsSlightlyLateOnes() {
        let now = romeDate(2026, 11, 7, 12, 0)
        let list = [transit("12:20"), transit("11:50"), transit("11:59"), transit("11:55", ritardo: 6 * 60), transit("12:05")]
        let sorted = list.upcomingSorted(now: now)
        XCTAssertEqual(sorted.map(\.adjustedDisplayTime), ["11:59", "12:01", "12:05", "12:20"])
    }

    func testDestinationStripsCotralCodes() {
        XCTAssertEqual(StopText.locality("FROSINONE | Piazza Pertini (f3486)"), "FROSINONE")
        XCTAssertEqual(StopText.locality("Cristoforo Colombo (ff90006)"), "Cristoforo Colombo")
        XCTAssertEqual(StopText.locality("Acilia"), "Acilia")
        var train = transit("10:00")
        train.percorso = "RL_PSP-CC"
        XCTAssertEqual(train.lineAndDestinationLabel, "VELLETRI", "ASTRAL route codes are hidden from riders")
    }

    func testLenientDecodingOfMissingFields() throws {
        let decoded = try JSONDecoder().decode(Transit.self, from: Data(#"{"tempoTransito":"08:00","numeroOrdine":3}"#.utf8))
        XCTAssertEqual(decoded.tempoTransito, "08:00")
        XCTAssertEqual(decoded.numeroOrdine, "3")
        XCTAssertNil(decoded.vehicleCode)
        XCTAssertFalse(decoded.canTrackVehicle)
    }
}

final class AstralDepartureTests: XCTestCase {
    private func departure(_ time: String) -> AstralDeparture {
        AstralDeparture(id: time, time: time, sortSeconds: (RomeTime.minutesOfDay(time) ?? 0) * 60, delayMinutes: nil, isCancelled: false, isReplacementBus: false)
    }

    func testUpcomingDropsPastEntriesAndSorts() {
        let entries = [departure("20:11"), departure("05:15"), departure("19:31"), departure("19:51")]
        XCTAssertEqual(entries.upcoming(from: romeDate(2026, 9, 18, 19, 0)).map(\.time), ["19:31", "19:51", "20:11"])
    }

    func testUpcomingKeepsAnEntryExactlyNow() {
        XCTAssertEqual([departure("19:31")].upcoming(from: romeDate(2026, 9, 18, 19, 31)).map(\.time), ["19:31"])
    }

    func testUpcomingEmptyAtNight() {
        XCTAssertTrue([departure("05:15")].upcoming(from: romeDate(2026, 9, 18, 23, 0)).isEmpty)
    }

    func testDecodingFillsMissingOptionalFields() throws {
        let decoded = try JSONDecoder().decode(AstralDeparture.self, from: Data(#"{"time":"07:05"}"#.utf8))
        XCTAssertEqual(decoded.id, "07:05")
        XCTAssertEqual(decoded.sortSeconds, 7 * 3600 + 5 * 60)
        XCTAssertNil(decoded.delayMinutes)
        XCTAssertFalse(decoded.isCancelled)
    }
}

final class GeoTests: XCTestCase {
    func testPolylineDecodesGoogleReferenceExample() {
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 1e-6)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 1e-6)
        XCTAssertEqual(points[1].latitude, 40.7, accuracy: 1e-6)
        XCTAssertEqual(points[1].longitude, -120.95, accuracy: 1e-6)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 1e-6)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 1e-6)
    }

    func testPolylineToleratesTruncatedInput() {
        XCTAssertEqual(Polyline.decode("").count, 0)
        XCTAssertEqual(Polyline.decode("_p~iF~ps|U_ulL").count, 1)
    }

    func testZoomMatchesWebMapScale() {
        // 360° across 256 pt is zoom 0; halving the span adds one level.
        XCTAssertEqual(MapViewport.zoom(longitudeDelta: 360, widthPoints: 256), 0, accuracy: 1e-9)
        XCTAssertEqual(MapViewport.zoom(longitudeDelta: 360.0 / 8192, widthPoints: 256), 13, accuracy: 1e-9)
        // log2(360 · 402 / 256 / 0.0275) ≈ 14.33 (an iPhone showing ~2 km across).
        XCTAssertEqual(MapViewport.zoom(longitudeDelta: 0.0275, widthPoints: 402), 14.33, accuracy: 0.01)
    }

    func testPaddedBoundsContain() {
        let bounds = ViewportBounds(minLat: 41.89, maxLat: 41.91, minLon: 12.49, maxLon: 12.51)
        XCTAssertTrue(bounds.padded.contains(bounds))
        XCTAssertTrue(bounds.padded.contains(CLLocationCoordinate2D(latitude: 41.915, longitude: 12.5)))
        XCTAssertFalse(bounds.padded.contains(CLLocationCoordinate2D(latitude: 42.0, longitude: 12.5)))
    }
}

final class VehicleLogicTests: XCTestCase {
    private func vehicle(_ id: String, lat: Double = 41.9, lon: Double = 12.5, route: String? = "211", op: TransitOperator = .atac) -> TransitVehicle {
        TransitVehicle(id: id, latitude: lat, longitude: lon, bearing: nil, routeId: route, routeLabel: route, kind: .bus,
                       transitOperator: op, delaySeconds: nil, tripId: nil, headsign: nil, vehicleCode: nil)
    }

    private let cityViewport = MapViewport(bounds: ViewportBounds(minLat: 41.89, maxLat: 41.91, minLon: 12.49, maxLon: 12.51), zoom: 15)

    func testViewportFilterKeepsNearbyVehiclesOnly() {
        let all = [vehicle("near"), vehicle("far", lat: 42.5, lon: 13.0)]
        XCTAssertEqual(MapViewModel.visibleVehicles(all, focusRouteId: nil, viewport: cityViewport).map(\.id), ["near"])
    }

    func testFocusShowsTheLineEverywhereAtAnyZoom() {
        let all = [vehicle("a", route: "211"), vehicle("b", lat: 42.5, lon: 13, route: "211"), vehicle("c", route: "64")]
        let zoomedOut = MapViewport(bounds: cityViewport.bounds, zoom: 8)
        XCTAssertEqual(Set(MapViewModel.visibleVehicles(all, focusRouteId: "211", viewport: zoomedOut).map(\.id)), ["a", "b"])
    }

    func testNoAmbientVehiclesWhenZoomedFarOut() {
        let zoomedOut = MapViewport(bounds: cityViewport.bounds, zoom: Config.minVehicleZoom - 0.5)
        XCTAssertTrue(MapViewModel.visibleVehicles([vehicle("a")], focusRouteId: nil, viewport: zoomedOut).isEmpty)
        XCTAssertTrue(MapViewModel.visibleVehicles([vehicle("a")], focusRouteId: nil, viewport: nil).isEmpty)
    }

    func testCotralMergeKeepsAMissingVehicleForTwoScansThenDropsIt() {
        let threshold = 2
        var state = CotralViewportVehicleService.merge(previous: [:], previousMisses: [:], fresh: [vehicle("t1", op: .cotral)], lossThreshold: threshold)
        XCTAssertEqual(state.byId.keys.sorted(), ["t1"])
        state = CotralViewportVehicleService.merge(previous: state.byId, previousMisses: state.misses, fresh: [], lossThreshold: threshold)
        XCTAssertEqual(state.misses["t1"], 1)
        state = CotralViewportVehicleService.merge(previous: state.byId, previousMisses: state.misses, fresh: [], lossThreshold: threshold)
        XCTAssertEqual(state.misses["t1"], 2)
        state = CotralViewportVehicleService.merge(previous: state.byId, previousMisses: state.misses, fresh: [], lossThreshold: threshold)
        XCTAssertTrue(state.byId.isEmpty)
    }

    func testCotralMergeResetsMissesWhenSeenAgain() {
        var state = CotralViewportVehicleService.merge(previous: ["t1": vehicle("t1")], previousMisses: ["t1": 2], fresh: [vehicle("t1", lat: 41.95)], lossThreshold: 2)
        XCTAssertEqual(state.misses["t1"], 0)
        XCTAssertEqual(state.byId["t1"]?.latitude, 41.95)
        state = CotralViewportVehicleService.merge(previous: state.byId, previousMisses: state.misses, fresh: [], lossThreshold: 2)
        XCTAssertNotNil(state.byId["t1"])
    }

    func testBadgeLabels() {
        XCTAssertEqual(vehicle("a", route: "64").badgeLabel, "64")
        XCTAssertNil(vehicle("a", route: "1234").badgeLabel)
        XCTAssertNil(vehicle("a", route: nil).badgeLabel)
    }

    func testStopGroupingKeepsEveryPlatform() {
        let stops = [
            AtacStop(stopId: "2", stopName: "COLOSSEO", lat: 0, lon: 0),
            AtacStop(stopId: "1", stopName: "COLOSSEO ", lat: 0, lon: 0),
            AtacStop(stopId: "3", stopName: "LABICANA", lat: 0, lon: 0),
        ]
        let groups = groupedStopsByName(stops)
        XCTAssertEqual(groups.map(\.name), ["COLOSSEO", "LABICANA"])
        XCTAssertEqual(groups[0].stops.map(\.stopId), ["1", "2"])
        XCTAssertEqual(groups[0].anchor.stopId, "1")
    }

    func testPoleMergeKeepsStaticCode() {
        let pole = Pole(cotralId: "f3583", name: "ROMA, Anagnina", locality: nil, lat: 41.84, lon: 12.58, rail: false)
        let info = CotralPoleInfo(code: "999", name: "", stopName: "Anagnina Metro A", locality: "Roma Anagnina", comune: "Roma", lat: 0, lon: 0)
        let merged = pole.merged(with: info)
        XCTAssertEqual(merged.id, "f3583")
        XCTAssertEqual(merged.nomePalina, "ROMA, Anagnina", "an empty upstream name must not erase the static one")
        XCTAssertEqual(merged.comune, "Roma")
        XCTAssertEqual(merged.coordX, 41.84, "a 0,0 upstream position is ignored")
        XCTAssertEqual(merged.localita, "Roma Anagnina")
    }
}

final class RouteTitleTests: XCTestCase {
    private func route(_ source: String, _ id: String, short: String, long: String, display: String, kind: TransitVehicleKind, rail: Bool = false) -> RouteInfo {
        RouteInfo(source: source, routeId: id, shortName: short, longName: long, displayName: display, kind: kind,
                  transitOperator: source == "cotral" ? .cotral : .atac, colorHex: nil, rail: rail)
    }

    func testTitlesShowWhatRidersRecognise() {
        let bus = route("atac", "011", short: "011", long: "ROMAGNOLI - SCAVI OSTIA ANTICA", display: "ROMAGNOLI - SCAVI OSTIA ANTICA", kind: .bus)
        XCTAssertEqual(bus.title, "011")
        XCTAssertEqual(bus.subtitleName, "ROMAGNOLI - SCAVI OSTIA ANTICA")
        let metro = route("atac", "MEA", short: "MEA", long: "", display: "Metro A", kind: .metro)
        XCTAssertEqual(metro.title, "Metro A")
        XCTAssertNil(metro.subtitleName)
        let rail = route("cotral", "F:ROMALIDO", short: "ROMALIDO", long: "METROMARE", display: "ROMALIDO", kind: .treno, rail: true)
        XCTAssertEqual(rail.title, "METROMARE")
        XCTAssertNil(rail.subtitleName)
    }

}

final class InitialViewportTests: XCTestCase {
    /// Regression: without a location fix the initial Rome view was ~6 km
    /// wide (zoom ≈ 12.96 on an iPhone), below the data threshold, so the map
    /// opened empty. The initial 4 km view must load stops on any iPhone width.
    func testInitialRomeViewIsAboveTheDataZoomThreshold() {
        let lonDelta = 4000 / (111_320 * cos(41.9028 * .pi / 180))
        for width in [320.0, 375, 402, 440] {
            XCTAssertGreaterThanOrEqual(MapViewport.zoom(longitudeDelta: lonDelta, widthPoints: width), Config.minDataZoom, "width \(width)")
        }
    }
}

final class LineOrderTests: XCTestCase {
    /// Since Nov 2026 the backend's `line` returns Atac stops in route order:
    /// direction 0 first, then the opposite platforms (same names). Grouping
    /// by name must keep that order, and the new `directions` field must not
    /// break decoding.
    func testRouteOrderSurvivesDecodingAndGrouping() throws {
        let json = #"""
        {"route":{"source":"atac","id":"MEA","shortName":"MEA","longName":"","displayName":"Metro A","kind":"metro","operator":"Atac","color":"E27439","rail":false},
         "stops":[{"id":"AD27","name":"Anagnina","lat":0,"lon":0,"headsign":"Battistini"},
                  {"id":"AD26","name":"Cinecitta'","lat":0,"lon":0,"headsign":"Battistini"},
                  {"id":"AD1","name":"Battistini","lat":0,"lon":0,"headsign":"Battistini"},
                  {"id":"AP1","name":"Battistini","lat":0,"lon":0,"headsign":"Anagnina"},
                  {"id":"AP26","name":"Cinecitta'","lat":0,"lon":0,"headsign":"Anagnina"},
                  {"id":"AP27","name":"Anagnina","lat":0,"lon":0,"headsign":"Anagnina"}],
         "shapes":[],
         "directions":[{"directionId":0,"headsign":"Battistini","stopIds":["AD27","AD26","AD1"]},{"directionId":1,"headsign":"Anagnina","stopIds":["AP1","AP26","AP27"]}]}
        """#
        let response = try JSONDecoder().decode(LineResponse.self, from: Data(json.utf8))
        let groups = groupedStopsByName(response.stops.map(\.asAtacStop))
        XCTAssertEqual(groups.map(\.name), ["Anagnina", "Cinecitta'", "Battistini"])
        XCTAssertEqual(groups[0].stops.count, 2, "both platforms of a station stay together")
    }
}
