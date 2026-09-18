import Foundation

/// One upcoming arrival at an Atac/Roma TPL stop — usually built from the
/// live `trip_updates` GTFS-Realtime feed, or (`isScheduled == true`) as a
/// best-effort static-timetable estimate when that stop has no live update
/// at all (see `AtacGtfsStore.scheduledDepartures(forStopId:)`).
struct AtacStopPrediction: Identifiable, Hashable {
    let tripId: String
    let routeId: String
    let routeLabel: String
    let kind: TransitVehicleKind
    let arrival: Date
    /// Seconds of delay Cotral-style (positive = late, negative = early).
    /// Always nil for a scheduled-fallback estimate.
    let delaySeconds: Int?
    var isScheduled: Bool = false
    /// The trip's destination (e.g. "Anagnina"), when known — see
    /// `AtacGtfsStore.headsign(forTripId:)`/`headsign(forRouteId:stopId:)`.
    var headsign: String? = nil

    var id: String { tripId }

    var minutesFromNow: Int {
        Int(arrival.timeIntervalSinceNow / 60)
    }

    /// "HH:mm" in Rome's own timezone, not the device's — matches
    /// `Transit.displayTime`'s reasoning on the Cotral rail side.
    var arrivalTimeLabel: String {
        Self.timeFormatter.string(from: arrival)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        return formatter
    }()
}
