import Foundation

/// A single "next departure" reading, normalized across the 3 sources a
/// Promemoria can target — Cotral bus (PIV.do), Cotral rail (ASTRAL), and
/// Atac/Roma TPL bus/tram (GTFS-Realtime `trip_updates`). Atac metro is
/// deliberately unsupported: neither GTFS-RT feed carries per-stop
/// predictions for it (confirmed against the project's own README), so
/// there is nothing to normalize.
struct ReminderDepartureStatus {
    /// "HH:mm", for the notification title.
    let time: String
    /// nil = unknown (no live delay reported for this run), 0 = on time,
    /// >0 = late. Never negative — an early arrival isn't worth flagging in
    /// a reminder the way a late or cancelled one is.
    let delayMinutes: Int?
    let isCancelled: Bool
    /// Only set when `isCancelled` — the following departure's time, for
    /// the notification's "Prossimo utile: HH:MM" line. Nil if there simply
    /// isn't a next one (service ending for the day).
    let nextUsefulTime: String?
}

private struct RawEntry {
    let time: String
    let delayMinutes: Int?
    let isCancelled: Bool
}

extension ReminderDepartureStatus {
    private static func combine(_ entries: [RawEntry]) -> ReminderDepartureStatus? {
        guard let first = entries.first else { return nil }
        return ReminderDepartureStatus(
            time: first.time,
            delayMinutes: first.delayMinutes,
            isCancelled: first.isCancelled,
            nextUsefulTime: first.isCancelled ? entries.dropFirst().first?.time : nil
        )
    }

    /// Cotral bus: picks the next not-yet-passed runs from a pole's live
    /// `Transit` list (same delay-aware "already passed" reasoning as
    /// `PoleDetailViewModel`'s own filter, reusing `Transit.minutesFromNow`
    /// rather than re-deriving it) and reads `soppressa` — confirmed live
    /// via `curl` against PIV.do as a raw "Y"/"N" string, parsed here for
    /// the first time anywhere in the app (existing views never checked it).
    static func nextUpcoming(from transits: [Transit]) -> ReminderDepartureStatus? {
        let sorted = transits
            .filter { ($0.minutesFromNow ?? -1) >= 0 }
            .sorted { ($0.minutesFromNow ?? .max) < ($1.minutesFromNow ?? .max) }
        return combine(sorted.map { transit in
            RawEntry(
                time: transit.adjustedDisplayTime,
                delayMinutes: transit.isDelayReliable ? max(0, transit.ritardoSeconds / 60) : nil,
                isCancelled: transit.soppressa.trimmingCharacters(in: .whitespaces).uppercased() == "Y"
            )
        })
    }

    /// Cotral rail: `AstralDeparture`'s own fields already match this shape
    /// almost exactly, having been designed for the same "puntuale/
    /// ritardo/soppressa" presentation elsewhere in the app
    /// (`AstralDepartureRow`). `entries` must already be sorted soonest
    /// first — pass `[AstralDeparture].upcoming()`'s result.
    static func nextUpcoming(from entries: [AstralDeparture]) -> ReminderDepartureStatus? {
        combine(entries.map { departure in
            RawEntry(time: departure.time, delayMinutes: departure.delayMinutes.map { max(0, $0) }, isCancelled: departure.isCancelled)
        })
    }

    /// Atac bus/tram, from the lean `AtacStopArrivalClient` lookup — no
    /// `AtacGtfsStore` involved (see that file's own doc comment for why).
    /// `arrivals` must already be sorted soonest first (its own
    /// `upcomingArrivals(stopId:limit:)` already returns them that way).
    static func nextUpcoming(from arrivals: [AtacStopArrival]) -> ReminderDepartureStatus? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return combine(arrivals.map { arrival in
            RawEntry(
                time: formatter.string(from: arrival.time),
                delayMinutes: arrival.delaySeconds.map { max(0, $0 / 60) },
                isCancelled: arrival.isCancelled
            )
        })
    }
}
