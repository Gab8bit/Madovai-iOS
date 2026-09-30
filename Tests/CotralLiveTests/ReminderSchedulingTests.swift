import XCTest
@testable import CotralLive

/// `ReminderScheduler.nextFireDate(for:after:)` is the pure date-math core
/// of the background-scheduling chain (see that type's doc comment for why
/// there's a chain at all) — everything else in `ReminderScheduler` talks to
/// `BGTaskScheduler`, which isn't unit-testable, so this is the piece worth
/// locking down with tests.
final class ReminderSchedulingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return calendar.date(from: components)!
    }

    private func reminder(weekdays: Set<Weekday>, hour: Int, minute: Int) -> Reminder {
        Reminder(stopName: "Test", weekdays: weekdays, hour: hour, minute: minute, source: .cotralBus(poleCode: "1"))
    }

    func testNilWhenNoWeekdaysSelected() {
        let reminder = reminder(weekdays: [], hour: 8, minute: 0)
        XCTAssertNil(ReminderScheduler.nextFireDate(for: reminder, after: date(2026, 9, 30, 7, 0), calendar: calendar))
    }

    func testRollsToNextDayWhenTimeAlreadyPassedToday() {
        // 2026-09-30 is a Wednesday. A daily reminder for 08:00, checked at
        // 09:00 the same day, must roll to tomorrow — not fire "in the past".
        let reminder = reminder(weekdays: Set(Weekday.allCases), hour: 8, minute: 0)
        let next = ReminderScheduler.nextFireDate(for: reminder, after: date(2026, 9, 30, 9, 0), calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 1, 8, 0))
    }

    func testFiresLaterTodayWhenTimeHasNotPassedYet() {
        let reminder = reminder(weekdays: Set(Weekday.allCases), hour: 18, minute: 30)
        let next = ReminderScheduler.nextFireDate(for: reminder, after: date(2026, 9, 30, 9, 0), calendar: calendar)
        XCTAssertEqual(next, date(2026, 9, 30, 18, 30))
    }

    func testPicksEarliestAcrossMultipleWeekdays() {
        // 2026-09-30 is Wednesday. Reminder set for Mon/Fri at 07:00,
        // checked on Wednesday — the earliest upcoming occurrence is Friday,
        // not the Monday that already passed this week.
        let reminder = reminder(weekdays: [.monday, .friday], hour: 7, minute: 0)
        let next = ReminderScheduler.nextFireDate(for: reminder, after: date(2026, 9, 30, 9, 0), calendar: calendar)
        XCTAssertEqual(next, date(2026, 10, 2, 7, 0))
    }

    func testWeekdayRawValuesMatchCalendarConvention() {
        // Calendar.Component.weekday is 1=Sunday in the Gregorian calendar —
        // `Weekday` must match exactly, or `nextFireDate` silently targets
        // the wrong day.
        XCTAssertEqual(Weekday.sunday.rawValue, 1)
        XCTAssertEqual(Weekday.saturday.rawValue, 7)
        XCTAssertEqual(calendar.component(.weekday, from: date(2026, 9, 30, 0, 0)), Weekday.wednesday.rawValue)
    }
}
