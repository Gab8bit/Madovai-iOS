import Foundation

/// One scheduled passage at a Cotral rail station (the backend's `Entry`):
/// from ASTRAL (real per-run delay, cancellations, replacement buses) or,
/// when ASTRAL can't resolve the station, from the static GTFS timetable
/// (then `delayMinutes` is always nil).
struct AstralDeparture: Codable, Identifiable, Hashable {
    let id: String
    /// "HH:MM" Rome, at this station.
    let time: String
    /// Seconds since Rome midnight, for sorting/filtering.
    let sortSeconds: Int
    /// Positive = late, negative = early; nil = not known (never "on time").
    let delayMinutes: Int?
    let isCancelled: Bool
    let isReplacementBus: Bool

    init(id: String, time: String, sortSeconds: Int, delayMinutes: Int?, isCancelled: Bool, isReplacementBus: Bool) {
        self.id = id
        self.time = time
        self.sortSeconds = sortSeconds
        self.delayMinutes = delayMinutes
        self.isCancelled = isCancelled
        self.isReplacementBus = isReplacementBus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = (try? c.decode(String.self, forKey: .time)) ?? ""
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? time
        sortSeconds = (try? c.decodeIfPresent(Int.self, forKey: .sortSeconds)) ?? ((RomeTime.minutesOfDay(time) ?? 0) * 60)
        delayMinutes = try? c.decodeIfPresent(Int.self, forKey: .delayMinutes)
        isCancelled = (try? c.decodeIfPresent(Bool.self, forKey: .isCancelled)) ?? false
        isReplacementBus = (try? c.decodeIfPresent(Bool.self, forKey: .isReplacementBus)) ?? false
    }
}

/// One direction's departures from a rail station (`rail` → `directions[]`).
struct AstralScheduleDirection: Codable, Identifiable, Hashable {
    let destination: String
    /// ASTRAL route code (e.g. "RL_PSP-CC"), when the backend knows it.
    let route: String?
    let entries: [AstralDeparture]

    var id: String { destination }
    var trainRoute: CotralTrainRoute? { route.flatMap(CotralTrainRoute.init(rawValue:)) }
}

extension Array where Element == AstralDeparture {
    /// The backend returns a station's *entire* day: keep only what's still
    /// ahead of now (Rome time), soonest first.
    func upcoming(from now: Date = Date()) -> [AstralDeparture] {
        let nowSeconds = RomeTime.secondsSinceMidnight(now)
        return filter { $0.sortSeconds >= nowSeconds }.sorted { $0.sortSeconds < $1.sortSeconds }
    }
}
