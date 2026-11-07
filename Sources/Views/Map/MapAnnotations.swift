import MapKit
import UIKit

// MARK: - Annotations (model objects)

final class PoleAnnotation: NSObject, MKAnnotation {
    private(set) var pole: Pole
    var isFavorite: Bool
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { pole.displayName }

    init(pole: Pole, isFavorite: Bool) {
        self.pole = pole
        self.isFavorite = isFavorite
        self.coordinate = pole.coordinate ?? CLLocationCoordinate2D()
    }

    func update(pole: Pole) { self.pole = pole }
}

final class AtacStopAnnotation: NSObject, MKAnnotation {
    let stop: AtacStop
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { stop.stopName }

    init(stop: AtacStop) {
        self.stop = stop
        self.coordinate = stop.coordinate
    }
}

/// One ambient vehicle (Atac fleet or Cotral). The object is kept for the
/// vehicle's whole life on the map and only its coordinate moves — never
/// removed and re-added on refresh, which is what made markers flicker.
final class VehicleAnnotation: NSObject, MKAnnotation {
    var vehicle: TransitVehicle
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { vehicle.routeLabel.map { "Linea \($0)" } ?? vehicle.transitOperator.rawValue }

    init(vehicle: TransitVehicle) {
        self.vehicle = vehicle
        self.coordinate = vehicle.coordinate
    }
}

/// The single vehicle followed with "Segui".
final class FollowedVehicleAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var isTreno: Bool
    var isLost: Bool
    var title: String? { isTreno ? "Treno in tempo reale" : "Bus in tempo reale" }

    init(coordinate: CLLocationCoordinate2D, isTreno: Bool, isLost: Bool) {
        self.coordinate = coordinate
        self.isTreno = isTreno
        self.isLost = isLost
    }
}

/// Tags a polyline with the route it draws, so the renderer can colour it.
final class ShapePolyline: MKPolyline {
    var shapeId = ""
    var kind: TransitVehicleKind = .bus
    var colorHex: String?

    var strokeColor: UIColor {
        if let colorHex, let color = UIColor(hex: colorHex) { return color }
        switch kind {
        case .metro: return .systemRed
        case .tram: return .systemOrange
        case .treno: return .systemPurple
        case .bus: return .systemBlue
        }
    }
}

enum VehicleMarkerStyle: Equatable {
    /// Labelled badge (route number or icon).
    case badge
    /// Small dot, for wider zoom levels.
    case dot
}

// MARK: - Views

/// Common base: generous, invisible tap area around a smaller drawing, so a
/// marker is easy to hit with a finger even when it looks tiny. MapKit
/// selects annotations by the view's frame, so the frame *is* the hit area.
class TapFriendlyAnnotationView: MKAnnotationView {
    let drawing = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        backgroundColor = .clear
        drawing.isUserInteractionEnabled = false
        addSubview(drawing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func layout(hitSize: CGFloat, drawingSize: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: hitSize, height: hitSize)
        drawing.frame = CGRect(x: (hitSize - drawingSize) / 2, y: (hitSize - drawingSize) / 2, width: drawingSize, height: drawingSize)
        drawing.layer.cornerRadius = drawingSize / 2
        centerOffset = .zero
    }
}

final class AtacStopAnnotationView: TapFriendlyAnnotationView {
    static let reuseIdentifier = "AtacStop"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        layout(hitSize: 28, drawingSize: 13)
        drawing.backgroundColor = .systemOrange
        drawing.layer.borderWidth = 1.5
        drawing.layer.borderColor = UIColor.white.cgColor
        // Hidden only when actually overlapping another marker (the circle
        // is the drawn dot, not the larger tap area).
        displayPriority = .defaultHigh
        collisionMode = .circle
        zPriority = .defaultUnselected
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "map.atacStop"
    }

    override var annotation: MKAnnotation? {
        didSet { accessibilityLabel = (annotation as? AtacStopAnnotation).map { "Fermata \($0.stop.stopName)" } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class VehicleAnnotationView: TapFriendlyAnnotationView {
    static let reuseIdentifier = "Vehicle"

    private let icon = UIImageView()
    private let label = UILabel()
    private var style: VehicleMarkerStyle = .badge

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // Never hidden by collisions and always above stops/poles, so a
        // vehicle can't vanish while zooming nor be covered by a stop pin.
        displayPriority = .required
        collisionMode = .none
        zPriority = .max
        selectedZPriority = .max
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "map.vehicle"

        drawing.layer.borderColor = UIColor.white.cgColor
        drawing.layer.shadowColor = UIColor.black.cgColor
        drawing.layer.shadowOpacity = 0.25
        drawing.layer.shadowRadius = 2
        drawing.layer.shadowOffset = CGSize(width: 0, height: 1)

        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        drawing.addSubview(icon)

        label.font = .systemFont(ofSize: 10, weight: .heavy)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        drawing.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ vehicle: TransitVehicle, style: VehicleMarkerStyle) {
        if style != self.style || drawing.bounds.width == 0 {
            self.style = style
            switch style {
            case .badge:
                layout(hitSize: 40, drawingSize: 28)
                drawing.layer.borderWidth = 1.5
            case .dot:
                layout(hitSize: 28, drawingSize: 12)
                drawing.layer.borderWidth = 1
            }
            let inner = drawing.bounds.insetBy(dx: 6, dy: 6)
            icon.frame = inner
            label.frame = drawing.bounds.insetBy(dx: 2, dy: 2)
        }

        drawing.backgroundColor = Self.color(for: vehicle)
        accessibilityLabel = vehicle.routeLabel.map { "Veicolo linea \($0)" } ?? "Veicolo \(vehicle.transitOperator.rawValue)"
        guard style == .badge else {
            icon.isHidden = true
            label.isHidden = true
            return
        }
        if let text = vehicle.badgeLabel {
            label.text = text
            label.isHidden = false
            icon.isHidden = true
        } else {
            icon.image = UIImage(systemName: vehicle.kind.sfSymbolName)
            icon.isHidden = false
            label.isHidden = true
        }
    }

    static func color(for vehicle: TransitVehicle) -> UIColor {
        switch vehicle.transitOperator {
        case .cotral: return .systemOrange
        case .romaTpl: return .systemGreen
        case .atac:
            switch vehicle.kind {
            case .metro: return .systemRed
            case .tram: return .systemOrange
            case .treno: return .systemPurple
            case .bus: return .systemTeal
            }
        }
    }
}

final class FollowedVehicleAnnotationView: TapFriendlyAnnotationView {
    static let reuseIdentifier = "Followed"
    private let icon = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        layout(hitSize: 44, drawingSize: 40)
        displayPriority = .required
        collisionMode = .none
        zPriority = .max
        drawing.layer.borderWidth = 2.5
        drawing.layer.borderColor = UIColor.white.cgColor
        drawing.layer.shadowColor = UIColor.black.cgColor
        drawing.layer.shadowOpacity = 0.3
        drawing.layer.shadowRadius = 3
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        icon.frame = drawing.bounds.insetBy(dx: 10, dy: 10)
        drawing.addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(isTreno: Bool, isLost: Bool) {
        icon.image = UIImage(systemName: isTreno ? "tram.fill" : "bus.fill")
        UIView.animate(withDuration: 0.25) {
            self.drawing.backgroundColor = isLost ? .systemGray : .systemOrange
            self.alpha = isLost ? 0.65 : 1
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
