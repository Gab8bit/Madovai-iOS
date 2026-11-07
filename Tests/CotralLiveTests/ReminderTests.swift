import XCTest
@testable import CotralLive

/// The normalisation of a reminder's "next departure" (same rules as the
/// backend's DepartureStatus) and the background fetch against the API.
final class ReminderDepartureStatusTests: XCTestCase {
    private let now = romeDate(2026, 11, 7, 12, 0)

    private func transit(_ time: String, ritardo: Int = 0, soppressa: String = "N", monitorata: String = "1") -> Transit {
        Transit(idCorsa: UUID().uuidString, orarioPartenzaCorsa: time, soppressa: soppressa, tempoTransito: time,
                ritardoSeconds: ritardo, vehicleCode: "B1", vehicleAlive: true, monitorata: monitorata)
    }

    func testCotralBusPicksSoonestNotYetPassed() {
        let status = ReminderDepartureStatus.nextUpcoming(from: [transit("12:20"), transit("12:05"), transit("11:57")], now: now)
        XCTAssertEqual(status?.time, "12:05")
        XCTAssertEqual(status?.delayMinutes, 0)
    }

    func testCotralBusCancelledFallsBackToNextUseful() {
        let status = ReminderDepartureStatus.nextUpcoming(from: [transit("12:05", soppressa: "Y"), transit("12:15")], now: now)
        XCTAssertEqual(status, ReminderDepartureStatus(time: "12:05", delayMinutes: 0, isCancelled: true, nextUsefulTime: "12:15"))
    }

    func testCotralBusDelayOnlyWhenReliable() {
        XCTAssertEqual(ReminderDepartureStatus.nextUpcoming(from: [transit("12:05", ritardo: 185)], now: now)?.delayMinutes, 3)
        XCTAssertEqual(ReminderDepartureStatus.nextUpcoming(from: [transit("12:05", ritardo: 185)], now: now)?.time, "12:08")
        XCTAssertNil(ReminderDepartureStatus.nextUpcoming(from: [transit("12:05", ritardo: 300, monitorata: "0")], now: now)?.delayMinutes)
        XCTAssertEqual(ReminderDepartureStatus.nextUpcoming(from: [transit("12:05", ritardo: -180)], now: now)?.delayMinutes, 0, "early is never negative")
    }

    func testCotralBusNilWhenNothingUpcoming() {
        XCTAssertNil(ReminderDepartureStatus.nextUpcoming(from: [transit("11:00")], now: now))
    }

    func testTrainMapsFields() {
        let entries = [AstralDeparture(id: "1", time: "18:11", sortSeconds: 0, delayMinutes: nil, isCancelled: true, isReplacementBus: false),
                       AstralDeparture(id: "2", time: "18:31", sortSeconds: 0, delayMinutes: 4, isCancelled: false, isReplacementBus: false)]
        XCTAssertEqual(ReminderDepartureStatus.nextUpcoming(from: entries), ReminderDepartureStatus(time: "18:11", delayMinutes: nil, isCancelled: true, nextUsefulTime: "18:31"))
        XCTAssertNil(ReminderDepartureStatus.nextUpcoming(from: [AstralDeparture]()))
    }

    func testAtacSkipsPastArrivalsAndConvertsDelay() {
        let nowTs = Int(now.timeIntervalSince1970)
        let arrivals = [
            AtacArrival(tripId: "past", routeId: "64", routeLabel: "64", kind: .bus, ts: nowTs - 120, delaySeconds: 0, headsign: nil, cancelled: false),
            AtacArrival(tripId: "b", routeId: "64", routeLabel: "64", kind: .bus, ts: nowTs + 600, delaySeconds: 185, headsign: nil, cancelled: false),
        ]
        let status = ReminderDepartureStatus.nextUpcoming(from: arrivals, now: now)
        XCTAssertEqual(status?.time, "12:10")
        XCTAssertEqual(status?.delayMinutes, 3)
    }

    func testAtacOnlyCancelledHasNoNextUseful() {
        let nowTs = Int(now.timeIntervalSince1970)
        let arrival = AtacArrival(tripId: "a", routeId: "64", routeLabel: "64", kind: .bus, ts: nowTs + 60, delaySeconds: nil, headsign: nil, cancelled: true)
        let status = ReminderDepartureStatus.nextUpcoming(from: [arrival], now: now)
        XCTAssertEqual(status?.isCancelled, true)
        XCTAssertNil(status?.nextUsefulTime)
    }
}

final class ReminderStatusFetcherTests: XCTestCase {
    private var fetcher: ReminderStatusFetcher!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        fetcher = ReminderStatusFetcher(api: TestAPI.make())
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func reminder(_ source: ReminderSource) -> Reminder {
        Reminder(stopName: "Test", weekdays: [.monday], hour: 12, minute: 0, source: source)
    }

    func testTrainWithStationIdUsesTheRailDirectionOfItsRoute() async throws {
        TestAPI.route(["rail": .init(body: Samples.rail)])
        let status = try await fetcher.status(
            for: reminder(.cotralTrain(stationName: "Acilia", route: .metromarePortaSanPaoloToColombo, stopId: "RL_ACILIA")),
            now: romeDate(2026, 11, 7, 12, 30)
        )
        XCTAssertEqual(status, ReminderDepartureStatus(time: "12:36", delayMinutes: 3, isCancelled: true, nextUsefulTime: "12:51"))
        XCTAssertEqual(StubURLProtocol.recordedRequests.first?.queryValue("stop"), "RL_ACILIA")
    }

    func testTrainOtherDirection() async throws {
        TestAPI.route(["rail": .init(body: Samples.rail)])
        let status = try await fetcher.status(
            for: reminder(.cotralTrain(stationName: "Acilia", route: .metromareColomboToPortaSanPaolo, stopId: "RL_ACILIA")),
            now: romeDate(2026, 11, 7, 12, 30)
        )
        XCTAssertEqual(status?.time, "12:40")
        XCTAssertEqual(status?.delayMinutes, 2)
    }

    func testLegacyTrainReminderFallsBackToTheLineView() async throws {
        TestAPI.route(["astral-line": .init(body: Samples.astralLine)])
        let status = try await fetcher.status(
            for: reminder(.cotralTrain(stationName: "ACILIA", route: .metromarePortaSanPaoloToColombo)),
            now: romeDate(2026, 11, 7, 12, 30)
        )
        XCTAssertEqual(status, ReminderDepartureStatus(time: "12:44", delayMinutes: 1, isCancelled: false, nextUsefulTime: nil))
    }

    func testBusAndAtacSources() async throws {
        TestAPI.route(["cotral-transits": .init(body: Samples.transits), "atac-live": .init(body: Samples.atacLive)])
        let bus = try await fetcher.status(for: reminder(.cotralBus(poleCode: "f3583")), now: romeDate(2026, 11, 7, 12, 10))
        XCTAssertEqual(bus?.time, "12:16")
        XCTAssertEqual(bus?.delayMinutes, 1)

        let atac = try await fetcher.status(for: reminder(.atacStop(stopId: "70240")), now: Date(timeIntervalSince1970: 1794050490))
        XCTAssertEqual(atac?.isCancelled, true)
        XCTAssertEqual(atac?.time, RomeTime.hhmm(unix: 1794050780))
        XCTAssertEqual(atac?.nextUsefulTime, RomeTime.hhmm(unix: 1794051014))
    }

    func testNetworkFailureThrowsSoTheSchedulerRetries() async {
        StubURLProtocol.handler = { _ in .init(error: URLError(.notConnectedToInternet)) }
        do {
            _ = try await fetcher.status(for: reminder(.cotralBus(poleCode: "f1")))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? APIError)?.kind, .offline)
        }
    }

    func testPre2ReminderJSONStillDecodes() throws {
        // Exactly what 1.3.0 persisted for a train reminder (no stopId).
        let json = #"""
        [{"id":"4C2A7D37-6B7A-4C3F-9B47-2B1D0A4F7E11","stopName":"Acilia","weekdays":[2,3],"hour":7,"minute":30,
          "source":{"cotralTrain":{"stationName":"Acilia","route":"RL_PSP-CC"}}}]
        """#
        let reminders = try JSONDecoder().decode([Reminder].self, from: Data(json.utf8))
        XCTAssertEqual(reminders.first?.source, .cotralTrain(stationName: "Acilia", route: .metromarePortaSanPaoloToColombo, stopId: nil))
        XCTAssertEqual(reminders.first?.weekdays, [.monday, .tuesday])
    }

    func testDirectionMatchingFallsBackToDestinationName() {
        let directions = [AstralScheduleDirection(destination: "Cristoforo Colombo", route: nil, entries: [])]
        XCTAssertNotNil(ReminderStatusFetcher.direction(for: .metromarePortaSanPaoloToColombo, in: directions))
        XCTAssertNil(ReminderStatusFetcher.direction(for: .metromareColomboToPortaSanPaolo, in: directions))
    }
}

@MainActor
final class ReminderMigrationTests: XCTestCase {
    private let suiteName = "dev.gab8bit.madovai.ReminderMigrationTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testResolvesMissingStationIdsViaSearch() async {
        TestAPI.route(["search": .init(body: Samples.search)])
        let store = ReminderStore(defaults: defaults)
        store.add(Reminder(stopName: "Acilia", weekdays: [.monday], hour: 7, minute: 0, source: .cotralTrain(stationName: "Acilia", route: .metromarePortaSanPaoloToColombo)))
        store.add(Reminder(stopName: "Bus", weekdays: [.monday], hour: 7, minute: 0, source: .cotralBus(poleCode: "f1")))

        await store.resolveMissingTrainStationIds(api: TestAPI.make())

        XCTAssertEqual(store.reminders[0].source, .cotralTrain(stationName: "Acilia", route: .metromarePortaSanPaoloToColombo, stopId: "RL_ACILIA"))
        XCTAssertEqual(ReminderStore(defaults: defaults).reminders[0].source, store.reminders[0].source, "persisted")
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 1, "only train reminders without an id are looked up")
    }

    func testUnresolvableStationIsLeftAlone() async {
        TestAPI.route(["search": .init(body: #"{"stops":[],"routes":[]}"#)])
        let store = ReminderStore(defaults: defaults)
        let original = ReminderSource.cotralTrain(stationName: "Nowhere", route: .metromarePortaSanPaoloToColombo)
        store.add(Reminder(stopName: "Nowhere", weekdays: [.monday], hour: 7, minute: 0, source: original))
        await store.resolveMissingTrainStationIds(api: TestAPI.make())
        XCTAssertEqual(store.reminders[0].source, original)
    }
}
