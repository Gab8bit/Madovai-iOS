import Foundation

/// One scheduled passage at a Cotral rail station, from ASTRAL's
/// `/api/transit` — replaces the old cotralspa.it-widget-era
/// `TrainScheduleEntry`. Unlike that widget (which only ever said "In
/// orario"), ASTRAL reports a real per-run delay, cancellations, and
/// replacement-bus service.
struct AstralDeparture: Identifiable, Hashable {
    /// ASTRAL's own "corsa" id — a dynamically-inserted reinforcement run
    /// has no "RL"/"RN"/"RV" prefix (e.g. "5175" vs the usual "RL2173"),
    /// though this app doesn't currently surface that distinction in the UI.
    let id: String
    /// "HH:mm" arrival at this specific stop.
    let time: String
    let sortSeconds: Int
    /// Minutes of delay (positive = late, negative = early); `nil` when
    /// ASTRAL hasn't computed one yet (a just-inserted reinforcement run) or
    /// this entry came from the static-GTFS fallback tier instead of ASTRAL.
    let delayMinutes: Int?
    /// ASTRAL's "soppressa".
    let isCancelled: Bool
    /// ASTRAL's "busSostitutivo".
    let isReplacementBus: Bool
}

/// All of one direction's upcoming departures from a single rail station —
/// replaces the old `TrainScheduleDirection`.
struct AstralScheduleDirection: Identifiable, Hashable {
    let destination: String
    let entries: [AstralDeparture]

    var id: String { destination }
}

extension Array where Element == AstralDeparture {
    /// ASTRAL's `/api/transit` returns a station's *entire* day, so any
    /// caller that wants "what's coming up" (as opposed to the full
    /// timetable) needs to drop everything already past and re-sort —
    /// without this, picking `.first` off a raw response returns the day's
    /// very first run (e.g. 05:15), not the next one from now.
    func upcoming(from now: Date = Date(), calendar: Calendar = .current) -> [AstralDeparture] {
        let nowSeconds = Self.secondsSinceMidnight(now, calendar: calendar)
        return filter { $0.sortSeconds >= nowSeconds }.sorted { $0.sortSeconds < $1.sortSeconds }
    }

    private static func secondsSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }
}
