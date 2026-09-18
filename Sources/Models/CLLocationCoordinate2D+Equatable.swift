import CoreLocation

// CLLocationCoordinate2D doesn't conform to Equatable out of the box, but
// SwiftUI's `onChange(of:)` and our own annotation-diffing both need it.
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D {
    func isApproximately(_ other: CLLocationCoordinate2D?, tolerance: CLLocationDegrees = 0.0000005) -> Bool {
        guard let other else { return false }
        return abs(latitude - other.latitude) < tolerance && abs(longitude - other.longitude) < tolerance
    }
}
