import Foundation

/// Matches `Calendar`'s own `DateComponents.weekday` raw values directly (1
/// = Sunday in the Gregorian calendar) so scheduling never needs a
/// translation step between this and `Calendar.nextDate(after:matching:)` —
/// deliberately not a 1=Monday convention, even though the UI presents
/// Monday first.
enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Monday-first, matching how the form displays the weekday picker.
    static let mondayFirstOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var shortLabel: String {
        switch self {
        case .monday: return "Lun"
        case .tuesday: return "Mar"
        case .wednesday: return "Mer"
        case .thursday: return "Gio"
        case .friday: return "Ven"
        case .saturday: return "Sab"
        case .sunday: return "Dom"
        }
    }
}

/// Which of the 3 supported live sources a reminder targets, plus whatever
/// identifier that source's own repository needs at fetch time — Atac metro
/// is excluded at the form/search level (see `ReminderFormView`), since
/// neither GTFS-Realtime feed carries per-stop predictions for it.
enum ReminderSource: Codable, Hashable {
    /// `poleCode`: a Cotral GTFS `stop_id`, used verbatim as PIV.do's own
    /// pole code (see `GtfsStop.stopId`'s doc comment) — the pole is
    /// already directional by nature, no separate direction needed.
    case cotralBus(poleCode: String)
    /// A Cotral rail station needs an explicit direction, since ASTRAL
    /// schedules are per line+direction, not per physical station.
    case cotralTrain(stationName: String, route: CotralTrainRoute)
    /// A GTFS `stop_id` is already directional for Atac too (one
    /// `stop_id` per platform/direction).
    case atacStop(stopId: String)

    var isTrain: Bool {
        if case .cotralTrain = self { return true }
        return false
    }
}

struct Reminder: Codable, Identifiable, Hashable {
    let id: UUID
    /// Display name for the notification body — captured at creation time
    /// rather than re-resolved from a GTFS store at fire time, since the
    /// background task deliberately avoids loading those (see
    /// `AtacStopArrivalClient`'s doc comment).
    var stopName: String
    var weekdays: Set<Weekday>
    var hour: Int
    var minute: Int
    var source: ReminderSource

    init(id: UUID = UUID(), stopName: String, weekdays: Set<Weekday>, hour: Int, minute: Int, source: ReminderSource) {
        self.id = id
        self.stopName = stopName
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
        self.source = source
    }

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var weekdaysLabel: String {
        if weekdays.count == 7 { return "Tutti i giorni" }
        let ordered = Weekday.mondayFirstOrder.filter { weekdays.contains($0) }
        return ordered.map(\.shortLabel).joined(separator: " · ")
    }
}
