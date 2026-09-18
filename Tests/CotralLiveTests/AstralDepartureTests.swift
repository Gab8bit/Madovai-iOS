import XCTest
@testable import CotralLive

/// Covers `[AstralDeparture].upcoming()` — added after a live bug where
/// `CotralVehicleDetailSheet` picked `.entries.first` straight off ASTRAL's
/// full-day response, always showing the day's very first run (e.g. 05:15)
/// instead of the next one from now. `PoleDetailViewModel`'s own schedule
/// view had the same "drop what's already past" filter inline; both now
/// share this one implementation.
final class AstralDepartureTests: XCTestCase {
    private func departure(_ time: String, sortSeconds: Int) -> AstralDeparture {
        AstralDeparture(id: time, time: time, sortSeconds: sortSeconds, delayMinutes: nil, isCancelled: false, isReplacementBus: false)
    }

    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 18
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    func testUpcomingDropsEntriesBeforeNow() {
        let entries = [
            departure("05:15", sortSeconds: 5 * 3600 + 15 * 60),
            departure("13:00", sortSeconds: 13 * 3600),
            departure("19:31", sortSeconds: 19 * 3600 + 31 * 60),
        ]
        let upcoming = entries.upcoming(from: date(hour: 19, minute: 0))
        XCTAssertEqual(upcoming.map(\.time), ["19:31"])
    }

    func testUpcomingSortsAscendingRegardlessOfInputOrder() {
        let entries = [
            departure("20:11", sortSeconds: 20 * 3600 + 11 * 60),
            departure("19:31", sortSeconds: 19 * 3600 + 31 * 60),
            departure("19:51", sortSeconds: 19 * 3600 + 51 * 60),
        ]
        let upcoming = entries.upcoming(from: date(hour: 19, minute: 0))
        XCTAssertEqual(upcoming.map(\.time), ["19:31", "19:51", "20:11"])
    }

    func testUpcomingKeepsAnEntryStartingExactlyNow() {
        let entries = [departure("19:31", sortSeconds: 19 * 3600 + 31 * 60)]
        let upcoming = entries.upcoming(from: date(hour: 19, minute: 31))
        XCTAssertEqual(upcoming.map(\.time), ["19:31"])
    }

    func testUpcomingIsEmptyWhenEverythingHasAlreadyPassed() {
        let entries = [departure("05:15", sortSeconds: 5 * 3600 + 15 * 60)]
        XCTAssertTrue(entries.upcoming(from: date(hour: 23, minute: 0)).isEmpty)
    }
}
