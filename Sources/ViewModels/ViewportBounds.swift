import MapKit

/// A simple lat/lon bounding box — used instead of `MKCoordinateRegion`
/// directly so it can be trivially `Equatable` for SwiftUI `onChange`/diffing.
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

    /// Padded a bit beyond the visible edges so panning slightly doesn't
    /// immediately show empty edges before the next viewport update lands.
    var padded: ViewportBounds {
        let latPad = (maxLat - minLat) * 0.15 + Config.atacViewportPaddingDegrees
        let lonPad = (maxLon - minLon) * 0.15 + Config.atacViewportPaddingDegrees
        return ViewportBounds(minLat: minLat - latPad, maxLat: maxLat + latPad, minLon: minLon - lonPad, maxLon: maxLon + lonPad)
    }
}
