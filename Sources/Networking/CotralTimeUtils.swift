import Foundation

enum CotralTimeUtils {
    /// Cotral's raw XML gives these fields as integer seconds — mirrors the
    /// reference server's `convertToReadableTime`, which converts them to
    /// "HH:MM" (optionally "-HH:MM") before ever reaching a client. Since
    /// there's no server doing that anymore, the app does it itself.
    ///
    /// - Parameter wrapClockAt24: for actual times of day (departure/arrival/
    ///   transit time), GTFS-style seconds-since-midnight can exceed 24h for
    ///   a post-midnight trip on the same service day (e.g. "24:48"), which
    ///   reads as a nonsensical hour to a user — wrap those to real
    ///   wall-clock time ("00:48"). `Transit.minutesFromNow` already handles
    ///   the day-rollover correctly regardless of whether the raw hour was
    ///   wrapped, so this is purely a display fix. `ritardo` is a *duration*,
    ///   not a time of day, so it must never be wrapped this way — pass
    ///   `false` there.
    static func readableTime(fromSeconds raw: String, wrapClockAt24: Bool = true) -> String {
        guard let seconds = Int(raw.trimmingCharacters(in: .whitespaces)) else { return "00:00" }
        let sign = seconds < 0 ? "-" : ""
        let absValue = abs(seconds)
        let totalMinutes = absValue / 60
        var hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if wrapClockAt24 { hours %= 24 }
        return "\(sign)\(String(format: "%02d", hours)):\(String(format: "%02d", minutes))"
    }

    /// Cotral's cmd=1 endpoint has lat/lon swapped for many poles. In Lazio,
    /// latitude is ~41-43 and longitude ~11-14; if the "latitude" value is
    /// under 20 it's actually longitude. Mirrors the reference server's
    /// `normalizeLatLon` exactly.
    static func normalizeLatLon(_ lat: Double, _ lon: Double) -> (lat: Double, lon: Double) {
        if lat > 0 && lat < 20 && lon > 20 {
            return (lon, lat)
        }
        return (lat, lon)
    }
}
