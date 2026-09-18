import MapKit

/// One of potentially many simultaneous ambient vehicle markers (the full
/// Atac/Roma TPL fleet, plus whatever Cotral vehicles the opportunistic
/// viewport scan turned up) — distinct from `VehicleAnnotation`, which is
/// the single vehicle a user explicitly chose to follow from a pole sheet.
final class TransitVehicleAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var vehicle: TransitVehicle
    var title: String? { vehicle.routeLabel.map { "Linea \($0)" } ?? vehicle.transitOperator.rawValue }

    init(vehicle: TransitVehicle) {
        self.vehicle = vehicle
        self.coordinate = vehicle.coordinate
    }
}

final class TransitVehicleAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "TransitVehicleAnnotationView"

    private let circle = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        canShowCallout = true
        displayPriority = .required

        circle.frame = bounds
        circle.layer.cornerRadius = bounds.width / 2
        circle.layer.borderWidth = 1.5
        circle.layer.borderColor = UIColor.white.cgColor
        addSubview(circle)

        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        icon.frame = bounds.insetBy(dx: 6, dy: 6)
        addSubview(icon)

        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.frame = bounds.insetBy(dx: 2, dy: 2)
        addSubview(label)
    }

    func apply(_ vehicle: TransitVehicle) {
        icon.image = UIImage(systemName: vehicle.kind.sfSymbolName)
        circle.backgroundColor = Self.color(for: vehicle)

        // Short route numbers read better as text than as a generic glyph
        // at this marker size; longer labels (or none) fall back to the icon.
        if let label = vehicle.routeLabel, label.count <= 3 {
            self.label.text = label
            self.label.isHidden = false
            icon.isHidden = true
        } else {
            self.label.isHidden = true
            icon.isHidden = false
        }
    }

    private static func color(for vehicle: TransitVehicle) -> UIColor {
        switch vehicle.transitOperator {
        case .cotral: return .systemOrange
        case .atac:
            switch vehicle.kind {
            case .metro: return .systemRed
            case .tram: return .systemOrange
            case .treno: return .systemPurple
            case .bus: return .systemTeal
            }
        case .romaTpl: return .systemGreen
        }
    }
}
