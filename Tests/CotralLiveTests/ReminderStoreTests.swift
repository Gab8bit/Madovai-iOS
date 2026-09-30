import XCTest
@testable import CotralLive

/// CRUD + persistence, mirrors `FavoritesStoreTests`'s injected-`UserDefaults`
/// pattern — a plain string suite name, not `#file` (see that file's own
/// fix from earlier this session for why `#file` writes a stray real plist
/// next to the test source instead of an opaque domain).
@MainActor
final class ReminderStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "dev.gab8bit.madovai.ReminderStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeReminder(stopName: String = "Test") -> Reminder {
        Reminder(stopName: stopName, weekdays: [.monday], hour: 8, minute: 0, source: .cotralBus(poleCode: "123"))
    }

    func testAddPersistsAndReloads() {
        let store = ReminderStore(defaults: defaults)
        store.add(makeReminder())
        XCTAssertEqual(store.reminders.count, 1)

        let reloaded = ReminderStore(defaults: defaults)
        XCTAssertEqual(reloaded.reminders.count, 1)
        XCTAssertEqual(reloaded.reminders.first?.stopName, "Test")
    }

    func testUpdateReplacesMatchingReminder() {
        let store = ReminderStore(defaults: defaults)
        let reminder = makeReminder()
        store.add(reminder)

        var updated = reminder
        updated.stopName = "Changed"
        store.update(updated)

        XCTAssertEqual(store.reminders.count, 1)
        XCTAssertEqual(store.reminders.first?.stopName, "Changed")
    }

    func testDeleteRemovesReminder() {
        let store = ReminderStore(defaults: defaults)
        let reminder = makeReminder()
        store.add(reminder)
        store.delete(reminder)
        XCTAssertTrue(store.reminders.isEmpty)
    }

    func testMultipleReminderSourcesRoundTripThroughCodable() {
        let store = ReminderStore(defaults: defaults)
        store.add(Reminder(stopName: "Bus", weekdays: [.monday], hour: 7, minute: 30, source: .cotralBus(poleCode: "1")))
        store.add(Reminder(stopName: "Train", weekdays: [.tuesday], hour: 8, minute: 0, source: .cotralTrain(stationName: "Acilia", route: .metromarePortaSanPaoloToColombo)))
        store.add(Reminder(stopName: "Atac", weekdays: [.wednesday], hour: 9, minute: 15, source: .atacStop(stopId: "70123")))

        let reloaded = ReminderStore(defaults: defaults)
        XCTAssertEqual(reloaded.reminders.count, 3)
        XCTAssertEqual(reloaded.reminders.first(where: { $0.stopName == "Train" })?.source, .cotralTrain(stationName: "Acilia", route: .metromarePortaSanPaoloToColombo))
    }
}
