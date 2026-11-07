import CoreLocation
import MapKit

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D {
    func isApproximately(_ other: CLLocationCoordinate2D?, tolerance: CLLocationDegrees = 0.000_000_5) -> Bool {
        guard let other else { return false }
        return abs(latitude - other.latitude) < tolerance && abs(longitude - other.longitude) < tolerance
    }

    var isValidForMap: Bool {
        CLLocationCoordinate2DIsValid(self) && !(latitude == 0 && longitude == 0)
    }

    /// Distance in metres (great-circle), without allocating CLLocations.
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        MKMapPoint(self).distance(to: MKMapPoint(other))
    }
}

/// A lat/lon bounding box — `Equatable`, unlike `MKCoordinateRegion`, so it
/// can drive SwiftUI diffing directly.
struct ViewportBounds: Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    init(region: MKCoordinateRegion) {
        minLat = region.center.latitude - region.span.latitudeDelta / 2
        maxLat = region.center.latitude + region.span.latitudeDelta / 2
        minLon = region.center.longitude - region.span.longitudeDelta / 2
        maxLon = region.center.longitude + region.span.longitudeDelta / 2
    }

    /// Padded beyond the visible edges (15 % + ~1 km) so a small pan doesn't
    /// immediately show empty edges before the next load lands — same
    /// padding as the web app's `pad()`.
    var padded: ViewportBounds {
        let latPad = (maxLat - minLat) * 0.15 + 0.01
        let lonPad = (maxLon - minLon) * 0.15 + 0.01
        return ViewportBounds(minLat: minLat - latPad, maxLat: maxLat + latPad, minLon: minLon - lonPad, maxLon: maxLon + lonPad)
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLat && coordinate.latitude <= maxLat
            && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }

    /// True when `other` lies entirely inside this box.
    func contains(_ other: ViewportBounds) -> Bool {
        other.minLat >= minLat && other.maxLat <= maxLat && other.minLon >= minLon && other.maxLon <= maxLon
    }
}

/// The settled map viewport: what's visible plus a web-map-style zoom level
/// (0 = whole world, ~13 = a neighbourhood, ~16 = a few streets).
struct MapViewport: Equatable {
    let bounds: ViewportBounds
    let zoom: Double

    /// Web Mercator zoom for a longitude span shown across `widthPoints`
    /// (256-point tiles, same scale as Leaflet/OSM zoom levels).
    static func zoom(longitudeDelta: CLLocationDegrees, widthPoints: Double) -> Double {
        guard longitudeDelta > 0, widthPoints > 0 else { return 0 }
        return log2(360 * widthPoints / 256 / longitudeDelta)
    }
}

/// Google Encoded Polyline (precision 5), the format of every `coords`
/// string the backend returns for line shapes.
enum Polyline {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(encoded.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(bytes.count / 4)
        var index = 0
        var lat = 0
        var lon = 0
        while index < bytes.count {
            guard let dLat = nextValue(bytes, &index), let dLon = nextValue(bytes, &index) else { break }
            lat += dLat
            lon += dLon
            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return coordinates
    }

    private static func nextValue(_ bytes: [UInt8], _ index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while index < bytes.count {
            let byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }
        return nil
    }
}
