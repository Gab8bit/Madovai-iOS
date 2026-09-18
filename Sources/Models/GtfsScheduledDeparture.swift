import Foundation

/// A single scheduled (not live) departure for a Cotral rail stop, computed
/// from static GTFS `stop_times.txt` + `calendar.txt`/`calendar_dates.txt`
/// for today's date — the last-resort tier of `PoleDetailViewModel`'s
/// 3-tier schedule fallback (live PIV.do transits, then the cotralspa.it
/// widget, then this), used only when neither of the other two has
/// anything for this stop. See `TrainScheduleEntry` for the model the pole
/// detail sheet actually renders, which this gets converted into.
struct GtfsScheduledDeparture: Identifiable, Hashable {
    let tripId: String
    let destinationStopName: String
    let departureSeconds: Int

    var id: String { tripId }

    var departureTime: String {
        let hours = (departureSeconds / 3600) % 24
        let minutes = (departureSeconds / 60) % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
