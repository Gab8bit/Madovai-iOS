import MapKit

/// One bus/train stop pole on the map.
final class PoleAnnotation: NSObject, MKAnnotation {
    let pole: Pole

    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { pole.displayName }
    var subtitle: String? { pole.subtitle }

    var poleCode: String { pole.id }
    var isFavorite: Bool

    init(pole: Pole, isFavorite: Bool) {
        self.pole = pole
        self.coordinate = pole.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self.isFavorite = isFavorite
    }
}
