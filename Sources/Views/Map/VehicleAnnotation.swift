import MapKit

/// The single live-tracked vehicle marker. `coordinate` is `@objc dynamic`
/// so wrapping an update in `UIView.animate` smoothly interpolates the
/// annotation view's on-screen position instead of jumping between points.
final class VehicleAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(coordinate: CLLocationCoordinate2D, title: String?) {
        self.coordinate = coordinate
        self.title = title
    }
}
