import MapKit
import UIKit

/// Tags an `MKPolyline` with the route it represents, so the renderer
/// delegate can color it by mode/GTFS `route_color` without a side lookup.
/// No custom `init` is added — the stored properties all have defaults, so
/// the subclass still gets `MKPolyline`'s own `init(coordinates:count:)` for
/// free (the standard pattern for tagging MapKit overlays).
final class AtacPolyline: MKPolyline {
    var routeId: String = ""
    var kind: TransitVehicleKind = .bus
    var colorHex: String?

    var strokeColor: UIColor {
        if let colorHex, let color = UIColor(hex: colorHex) {
            return color
        }
        switch kind {
        case .metro: return .systemRed
        case .tram: return .systemOrange
        case .treno: return .systemPurple
        case .bus: return .systemBlue
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.hasPrefix("#") ? String(sanitized.dropFirst()) : sanitized
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
