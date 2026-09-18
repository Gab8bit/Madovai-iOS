import Foundation

/// One scheduled train departure as shown in the pole detail sheet's
/// direction-split schedule view, normalized from whichever tier of
/// `PoleDetailViewModel`'s fallback chain produced it — the cotralspa.it
/// widget (tier 2) or the static GTFS timetable (tier 3). Live PIV.do
/// transits (tier 1, shown whenever available) are a separate, richer UI
/// (`TransitRowView`, with real per-train delay/tracking) and never go
/// through this type — this is only ever schedule data, not live data.
struct TrainScheduleEntry: Identifiable, Hashable {
    let id: String
    let time: String
    let sortSeconds: Int
}

/// Today's remaining departures for one direction (destination) from a
/// rail stop — a stop usually has two of these (one per direction of
/// travel), occasionally more when some trips short-turn partway down the
/// line. `entries` is already filtered to the current time and sorted.
struct TrainScheduleDirection: Identifiable, Hashable {
    let destination: String
    let entries: [TrainScheduleEntry]

    var id: String { destination }
}
