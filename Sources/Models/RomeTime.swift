import Foundation

/// Every schedule time in the API ("HH:MM", `sortSeconds`) is Rome wall-clock
/// time, so every "now" comparison must be too — otherwise a phone set to
/// another time zone would show nonsense "tra N min" values.
enum RomeTime {
    static let timeZone = TimeZone(identifier: "Europe/Rome")!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    /// (hour, minute, second) of `date` in Rome.
    static func clock(_ date: Date = Date()) -> (hour: Int, minute: Int, second: Int) {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static func secondsSinceMidnight(_ date: Date = Date()) -> Int {
        let c = clock(date)
        return c.hour * 3600 + c.minute * 60 + c.second
    }

    /// "HH:mm" in Rome for a date.
    static func hhmm(_ date: Date) -> String {
        let c = clock(date)
        return String(format: "%02d:%02d", c.hour, c.minute)
    }

    /// "HH:mm" in Rome for a unix timestamp (seconds).
    static func hhmm(unix ts: Int) -> String {
        hhmm(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Minutes from `now` until an "HH:MM" Rome time, with the schedule's
    /// own midnight-rollover convention (Cotral can write "25:10" for a run
    /// after midnight): a single ±12 h wrap brings any reading near zero.
    /// Nil if the string isn't "H:MM"/"HH:MM".
    static func minutesFromNow(_ time: String, now: Date = Date()) -> Int? {
        guard let target = minutesOfDay(time) else { return nil }
        let c = clock(now)
        var diff = target - (c.hour * 60 + c.minute)
        if diff > 12 * 60 { diff -= 24 * 60 }
        if diff < -12 * 60 { diff += 24 * 60 }
        return diff
    }

    static func minutesOfDay(_ time: String) -> Int? {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h >= 0, m >= 0, m < 60 else { return nil }
        return h * 60 + m
    }

    /// "HH:MM" + seconds, wrapped to a 24 h clock face (a delay can push a
    /// time past midnight or, for an early run just after midnight, back
    /// before it — the double modulo handles both).
    static func adding(seconds: Int, to time: String) -> String {
        guard let minutes = minutesOfDay(time) else { return time }
        let total = minutes * 60 + seconds
        let wrapped = ((total % 86400) + 86400) % 86400
        return String(format: "%02d:%02d", wrapped / 3600, (wrapped % 3600) / 60)
    }
}

/// Shared wording for "how far away" labels, identical everywhere.
enum RelativeTime {
    /// "tra N min" / "tra 1 min" / `passedLabel` for now-or-past.
    static func label(minutes: Int?, passedLabel: String = "in arrivo") -> String? {
        guard let minutes else { return nil }
        if minutes <= 0 { return passedLabel }
        if minutes == 1 { return "tra 1 min" }
        return "tra \(minutes) min"
    }

    /// Delay wording used by every row: nil under one minute (not worth
    /// surfacing), "in ritardo di N min" / "in anticipo di N min" otherwise.
    static func delayLabel(seconds: Int?) -> (text: String, isLate: Bool)? {
        guard let seconds, abs(seconds) >= 60 else { return nil }
        let minutes = abs(seconds) / 60
        return seconds > 0 ? ("in ritardo di \(minutes) min", true) : ("in anticipo di \(minutes) min", false)
    }

    /// ASTRAL delays are already whole minutes; 0 means "Puntuale".
    static func trainDelayLabel(minutes: Int?) -> (text: String, tone: DelayTone)? {
        guard let minutes else { return nil }
        if abs(minutes) < 1 { return ("Puntuale", .neutral) }
        return minutes > 0 ? ("In ritardo di \(minutes) min", .late) : ("In anticipo di \(abs(minutes)) min", .early)
    }

    enum DelayTone { case neutral, late, early }
}
