import Foundation

/// A single "next departure" reading, normalized across the 3 sources a
/// Promemoria can target — same shape and rules as the backend's
/// `DepartureStatus` (Madovai-Backend `src/live/departureStatus.ts`), so the
/// local notification reads exactly like the web app's push.
struct ReminderDepartureStatus: Equatable {
    /// "HH:mm", for the notification title.
    let time: String
    /// nil = unknown, 0 = on time, >0 = late. Never negative: an early
    /// arrival isn't worth flagging in a reminder.
    let delayMinutes: Int?
    let isCancelled: Bool
    /// Only when `isCancelled`: the following departure ("Prossimo utile").
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

    /// Cotral bus: next not-yet-passed runs (delay-aware), soonest first.
    static func nextUpcoming(from transits: [Transit], now: Date = Date()) -> ReminderDepartureStatus? {
        let sorted = transits.enumerated()
            .compactMap { index, transit -> (Int, Int, Transit)? in
                guard let minutes = transit.minutesFromNow(now: now), minutes >= 0 else { return nil }
                return (minutes, index, transit)
            }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return combine(sorted.map { _, _, transit in
            RawEntry(
                time: transit.adjustedDisplayTime,
                delayMinutes: transit.isDelayReliable ? max(0, transit.ritardoSeconds / 60) : nil,
                isCancelled: transit.isCancelled
            )
        })
    }

    /// Cotral rail: `entries` must already be upcoming-only, soonest first.
    static func nextUpcoming(from entries: [AstralDeparture]) -> ReminderDepartureStatus? {
        combine(entries.map { departure in
            RawEntry(time: departure.time, delayMinutes: departure.delayMinutes.map { max(0, $0) }, isCancelled: departure.isCancelled)
        })
    }

    /// Atac bus/tram: arrivals from now on, soonest first.
    static func nextUpcoming(from arrivals: [AtacArrival], now: Date = Date()) -> ReminderDepartureStatus? {
        let nowTs = Int(now.timeIntervalSince1970)
        let upcoming = arrivals.filter { $0.ts >= nowTs }.sorted { $0.ts < $1.ts }
        return combine(upcoming.map { arrival in
            RawEntry(
                time: arrival.timeLabel,
                delayMinutes: arrival.delaySeconds.map { max(0, $0 / 60) },
                isCancelled: arrival.cancelled
            )
        })
    }
}
