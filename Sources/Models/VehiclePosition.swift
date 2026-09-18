import CoreLocation

/// A single position record from Cotral's Automezzi.do (cmd=loc). `coordX`/
/// `coordY` are parallel arrays (a short trail of recent GPS pings), not a
/// single point — the latest reading is the last element of each.
struct VehiclePosition {
    /// Latitudes.
    var coordX: [String]
    /// Longitudes.
    var coordY: [String]
    var time: String

    /// Most recent valid coordinate in this record's trail, or nil if the
    /// trail is empty or only contains the (0,0) "no fix" placeholder.
    var latestCoordinate: CLLocationCoordinate2D? {
        guard let latString = coordX.last, let lonString = coordY.last,
              let lat = Double(latString), let lon = Double(lonString),
              !(lat == 0 && lon == 0)
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
