import XCTest
@testable import CotralLive

/// The whole API layer against stubbed HTTP: URL building, decoding of every
/// endpoint the app uses (bodies captured from the production backend) and
/// the mapping of HTTP/transport failures to user-facing errors.
final class APIClientTests: XCTestCase {
    private var api: MadovaiAPI!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        api = TestAPI.make()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: URL building

    func testTripIdHashIsPercentEncoded() async throws {
        TestAPI.route(["atac-trip": .init(body: Samples.atacTrip)])
        _ = try await api.atacTrip(tripId: "0#3280-9")
        let url = try XCTUnwrap(StubURLProtocol.recordedRequests.first?.url)
        XCTAssertTrue(url.absoluteString.contains("trip=0%233280-9"), url.absoluteString)
        XCTAssertEqual(url.path, "/api/v1/atac-trip")
    }

    func testSearchQueryWithSpacesAndAccentsIsEncoded() async throws {
        TestAPI.route(["search": .init(body: Samples.search)])
        _ = try await api.search("Città & co")
        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(request.queryValue("q"), "Città & co")
        XCTAssertFalse(request.url!.absoluteString.contains(" "))
    }

    func testEmptyQueryValuesAreOmitted() {
        let url = APIClient(baseURL: TestAPI.baseURL).url("atac-stop", query: ["id": "80725", "route": nil])
        XCTAssertEqual(url.absoluteString, "https://example.test/api/v1/atac-stop?id=80725")
    }

    func testHealthUsesServerRoot() async throws {
        StubURLProtocol.handler = { _ in .init(body: Samples.health) }
        let health = try await api.health()
        XCTAssertTrue(health.gtfsReady)
        XCTAssertEqual(StubURLProtocol.recordedRequests.first?.url?.absoluteString, "https://example.test/health")
    }

    // MARK: Decoding

    func testSearchDecodesStopsAndRoutes() async throws {
        TestAPI.route(["search": .init(body: Samples.search)])
        let result = try await api.search("acilia")
        XCTAssertEqual(result.stops.count, 3)
        XCTAssertTrue(result.stops[0].isCotral && result.stops[0].rail)
        XCTAssertTrue(result.stops[2].metro)
        XCTAssertEqual(result.routes[0].displayName, "Metro A")
        XCTAssertEqual(result.routes[0].kind, .metro)
        XCTAssertEqual(result.routes[0].colorHex, "E27439")
        XCTAssertEqual(result.routes[1].routeId, "F:ROMALIDO")
        XCTAssertEqual(result.routes[1].transitOperator, .cotral)
        XCTAssertNil(result.routes[1].colorHex)
    }

    func testStopsMapToPolesAndAtacStops() async throws {
        TestAPI.route(["stops": .init(body: Samples.stops)])
        let result = try await api.stops(in: ViewportBounds(minLat: 41.89, maxLat: 41.91, minLon: 12.49, maxLon: 12.51))
        XCTAssertEqual(result.poles.first?.codicePalina, "f14638")
        XCTAssertEqual(result.poles.first?.localita, "ROMA")
        XCTAssertEqual(result.poles.first?.isTreno, false)
        XCTAssertEqual(result.atacStops.map(\.stopId), ["80725", "80785"])
        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(request.queryValue("minLat"), "41.89000")
        XCTAssertEqual(request.queryValue("atacLimit"), "400")
    }

    func testCotralTransitsDecode() async throws {
        TestAPI.route(["cotral-transits": .init(body: Samples.transits)])
        let result = try await api.cotralTransits(pole: "f3583")
        XCTAssertEqual(result.pole?.comune, "Roma")
        XCTAssertEqual(result.transits.count, 2)
        let first = result.transits[0]
        XCTAssertEqual(first.vehicleCode, "4007")
        XCTAssertTrue(first.vehicleAlive)
        XCTAssertEqual(first.trackingStatus, .realtime)
        XCTAssertEqual(first.adjustedDisplayTime, "12:16")
        XCTAssertEqual(first.lineAndDestinationLabel, "FR766D · FROSINONE")
        let second = result.transits[1]
        XCTAssertNil(second.vehicleCode)
        XCTAssertTrue(second.isCancelled)
        XCTAssertEqual(second.trackingStatus, .scheduled)
    }

    func testEmptyTransitsWithNullPoleDecode() async throws {
        TestAPI.route(["cotral-transits": .init(body: Samples.emptyTransits)])
        let result = try await api.cotralTransits(pole: "f14638")
        XCTAssertNil(result.pole)
        XCTAssertTrue(result.transits.isEmpty)
    }

    func testRailDecodesDirectionsWithNullDelay() async throws {
        TestAPI.route(["rail": .init(body: Samples.rail)])
        let result = try await api.rail(stopId: "RL_ACILIA")
        XCTAssertEqual(result.source, "astral")
        XCTAssertEqual(result.directions.count, 2)
        XCTAssertEqual(result.directions[0].trainRoute, .metromarePortaSanPaoloToColombo)
        XCTAssertNil(result.directions[0].entries[2].delayMinutes)
        XCTAssertTrue(result.directions[0].entries[2].isReplacementBus)
    }

    func testAtacVehiclesDropInvalidCoordinatesAndEmptyHeadsigns() async throws {
        TestAPI.route(["atac-vehicles": .init(body: Samples.atacVehicles)])
        let result = try await api.atacVehicles()
        XCTAssertEqual(result.vehicles.map(\.id), ["atac-54", "atac-900", "tpl-7"])
        XCTAssertEqual(result.vehicles[2].transitOperator, .romaTpl)
        XCTAssertNil(result.vehicles[2].headsign)
        XCTAssertEqual(result.vehicles[1].lineName, "Metro A")
        XCTAssertEqual(result.updated, Date(timeIntervalSince1970: 1794050490))
    }

    func testCotralVehiclesDecode() async throws {
        TestAPI.route(["cotral-vehicles": .init(body: Samples.cotralVehicles)])
        let vehicles = try await api.cotralVehicles(poles: ["RL_ACILIA"])
        XCTAssertEqual(vehicles.first?.vehicleCode, "T395")
        XCTAssertEqual(vehicles.first?.kind, .treno)
        XCTAssertEqual(vehicles.first?.transitOperator, .cotral)
        XCTAssertEqual(vehicles.first?.lineName, "Metromare")
        XCTAssertNil(vehicles.first?.badgeLabel, "an ASTRAL route code must never be drawn as a badge label")
    }

    func testCotralVehiclesWithNoPolesDoesNotHitTheNetwork() async throws {
        let vehicles = try await api.cotralVehicles(poles: [])
        XCTAssertTrue(vehicles.isEmpty)
        XCTAssertTrue(StubURLProtocol.recordedRequests.isEmpty)
    }

    func testCotralVehiclesCapsPolesAtFifteen() async throws {
        TestAPI.route(["cotral-vehicles": .init(body: #"{"vehicles":[]}"#)])
        _ = try await api.cotralVehicles(poles: (1...20).map { "p\($0)" })
        let poles = StubURLProtocol.recordedRequests.first?.queryValue("poles")?.split(separator: ",")
        XCTAssertEqual(poles?.count, 15)
    }

    func testCotralVehiclePositionNullMeansUnknown() async throws {
        TestAPI.route(["cotral-vehicle": .init(body: #"{"lat":null,"lon":null}"#)])
        let position = try await api.cotralVehicle(code: "T1")
        XCTAssertNil(position)
    }

    func testAtacLiveSortsArrivalsAndKeepsCancellations() async throws {
        TestAPI.route(["atac-live": .init(body: Samples.atacLive)])
        let result = try await api.atacLive(stopIds: ["70240"])
        let arrivals = try XCTUnwrap(result["70240"])
        XCTAssertEqual(arrivals.map(\.routeLabel), ["82", "360"])
        XCTAssertTrue(arrivals[0].cancelled)
        XCTAssertNil(arrivals[0].delaySeconds)
        XCTAssertEqual(arrivals[1].delaySeconds, -224)
    }

    func testAtacLiveSplitsMoreThan150StopsIntoSeveralRequests() async throws {
        StubURLProtocol.handler = { request in
            let ids = request.queryValue("stops")?.split(separator: ",") ?? []
            XCTAssertLessThanOrEqual(ids.count, 150)
            let body = ids.map { "\"\($0)\":[]" }.joined(separator: ",")
            return .init(body: "{\"updated\":1,\"stops\":{\(body)}}")
        }
        let ids = (1...160).map { String($0) } + ["1", "2"]
        let result = try await api.atacLive(stopIds: ids)
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 2)
        XCTAssertEqual(result.count, 160)
    }

    func testAtacStopScheduleTripAndLineDecode() async throws {
        TestAPI.route([
            "atac-stop": .init(body: Samples.atacStop),
            "atac-schedule": .init(body: Samples.atacSchedule),
            "atac-trip": .init(body: Samples.atacTrip),
            "line": .init(body: Samples.line),
            "lines": .init(body: Samples.lines),
            "shapes": .init(body: Samples.shapes),
            "astral-line": .init(body: Samples.astralLine),
            "pole": .init(body: Samples.pole),
        ])
        let stop = try await api.atacStop(id: "80725")
        XCTAssertEqual(stop.stops.map(\.asAtacStop).map(\.headsign), ["Termini", "Tonino Bello"])

        let schedule = try await api.atacSchedule(stopId: "80725")
        XCTAssertEqual(schedule.first?.routeLabel, "514")
        XCTAssertFalse(schedule.first?.cancelled ?? true)
        XCTAssertNil(schedule.first?.delaySeconds)

        let trip = try await api.atacTrip(tripId: "0#3280-9")
        XCTAssertEqual(trip.stops.count, 2)
        XCTAssertNil(trip.stops[1].delaySeconds)

        let line = try await api.line(source: "atac", id: "MEA")
        XCTAssertEqual(line.shapes.first?.routeId, "MEA")
        XCTAssertEqual(line.shapes.first?.kind, .metro)
        XCTAssertEqual(line.shapes.first?.colorHex, "E27439")
        XCTAssertEqual(line.shapes.first?.coordinates.count, 3)

        let lines = try await api.lines()
        XCTAssertEqual(lines.cotralRail.first?.shortName, "ROMALIDO")

        let shapes = try await api.shapes(in: ViewportBounds(minLat: 0, maxLat: 1, minLon: 0, maxLon: 1))
        XCTAssertEqual(shapes.first?.routeId, "P02")

        let astral = try await api.astralLine(route: "RL_PSP-CC")
        XCTAssertNil(astral.stations.last?.next)

        let pole = try await api.pole(id: "RL_ACILIA")
        XCTAssertEqual(pole.trainRoutes, ["RL_CC-PSP", "RL_PSP-CC"])
    }

    // MARK: Errors

    func testBadRequestCarriesTheServerMessage() async {
        TestAPI.route(["line": .init(status: 400, body: #"{"error":"Linea inesistente"}"#)])
        await assertAPIError(kind: .badRequest, message: "Linea inesistente") { _ = try await self.api.line(source: "cotral", id: "XYZ") }
    }

    func testNotReadyAndRateLimited() async {
        TestAPI.route(["stops": .init(status: 503, body: #"{"error":"Dati statici non ancora pronti"}"#)])
        await assertAPIError(kind: .notReady, message: "Dati statici non ancora pronti") {
            _ = try await self.api.stops(in: ViewportBounds(minLat: 0, maxLat: 1, minLon: 0, maxLon: 1))
        }
        TestAPI.route(["search": .init(status: 429, body: #"{"error":"Troppe richieste"}"#)])
        await assertAPIError(kind: .rateLimited, message: "Troppe richieste") { _ = try await self.api.search("x") }
    }

    func testUpstreamFailureWithoutJSONBodyGetsAGenericItalianMessage() async {
        TestAPI.route(["cotral-transits": .init(status: 502, body: "<html>Bad gateway</html>")])
        await assertAPIError(kind: .server(502), message: "La fonte dei dati non risponde. Riprova tra qualche secondo.") {
            _ = try await self.api.cotralTransits(pole: "f1")
        }
    }

    func testOfflineAndTimeout() async {
        StubURLProtocol.handler = { _ in .init(error: URLError(.notConnectedToInternet)) }
        await assertAPIError(kind: .offline, message: APIError.offline.message) { _ = try await self.api.lines() }
        StubURLProtocol.handler = { _ in .init(error: URLError(.timedOut)) }
        await assertAPIError(kind: .timeout, message: APIError.timeout.message) { _ = try await self.api.lines() }
    }

    func testMalformedBodyIsADecodingError() async {
        TestAPI.route(["lines": .init(body: #"{"unexpected":true}"#)])
        await assertAPIError(kind: .decoding, message: APIError.decoding.message) { _ = try await self.api.lines() }
    }

    func testCancellationIsNotReportedAsAnError() {
        XCTAssertTrue(APIClient.map(URLError(.cancelled)) is CancellationError)
        XCTAssertTrue(CancellationError().isCancellation)
    }

    private func assertAPIError(kind: APIError.Kind, message: String, file: StaticString = #filePath, line: UInt = #line, _ body: @escaping () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected an error", file: file, line: line)
        } catch let error as APIError {
            XCTAssertEqual(error.kind, kind, file: file, line: line)
            XCTAssertEqual(error.message, message, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
