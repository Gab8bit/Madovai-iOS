import CoreLocation

struct AtacStop: Hashable, Identifiable {
    let stopId: String
    let stopName: String
    let lat: Double
    let lon: Double

    var id: String { stopId }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct AtacRoute: Hashable {
    let routeId: String
    let routeShortName: String
    let routeLongName: String
    let kind: TransitVehicleKind
    let transitOperator: TransitOperator
    /// Hex string (e.g. "FF6600") without "#", or nil if Roma's feed left
    /// it blank for this route — common in practice (see AtacGtfsParsing).
    let colorHex: String?
}

/// One drawable line segment: a specific shape (one branch/direction of a
/// route) with its ordered points, ready to become an `MKPolyline`.
struct AtacLineShape {
    let shapeId: String
    let routeId: String
    let coordinates: [CLLocationCoordinate2D]
    /// Rough bounding box, precomputed once for fast viewport intersection
    /// tests against hundreds of shapes on every map-region change.
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    init(shapeId: String, routeId: String, coordinates: [CLLocationCoordinate2D]) {
        self.shapeId = shapeId
        self.routeId = routeId
        self.coordinates = coordinates
        var minLat = Double.greatestFiniteMagnitude, maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude, maxLon = -Double.greatestFiniteMagnitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    func intersects(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> Bool {
        self.minLat <= maxLat && self.maxLat >= minLat && self.minLon <= maxLon && self.maxLon >= minLon
    }
}
