import MapKit

/// Custom marker for the live-tracked vehicle. Distinct from pole markers
/// on purpose, and visually dims + shows a status ring when live tracking
/// is lost, instead of silently leaving a stale marker looking "live".
final class VehicleAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "VehicleAnnotationView"

    private let circle = UIView()
    private let icon = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        centerOffset = .zero
        canShowCallout = true
        displayPriority = .required

        circle.frame = bounds
        circle.layer.cornerRadius = bounds.width / 2
        circle.layer.borderWidth = 2
        circle.layer.borderColor = UIColor.white.cgColor
        circle.backgroundColor = .systemOrange
        addSubview(circle)

        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        icon.image = UIImage(systemName: "bus.fill")
        icon.frame = bounds.insetBy(dx: 9, dy: 9)
        addSubview(icon)
    }

    func apply(trackingState: VehicleTrackingState) {
        switch trackingState {
        case .tracking, .idle:
            UIView.animate(withDuration: 0.25) {
                self.circle.backgroundColor = .systemOrange
                self.alpha = 1.0
            }
        case .lost:
            UIView.animate(withDuration: 0.25) {
                self.circle.backgroundColor = .systemGray
                self.alpha = 0.65
            }
        }
    }
}
