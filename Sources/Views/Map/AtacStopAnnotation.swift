import MapKit

final class AtacStopAnnotation: NSObject, MKAnnotation {
    let stop: AtacStop
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { stop.stopName }

    init(stop: AtacStop) {
        self.stop = stop
        self.coordinate = stop.coordinate
    }
}

/// Small, discreet dot — deliberately not a full marker balloon, so
/// hundreds of urban stops don't overwhelm the map the way Cotral's
/// sparser regional poles can afford to.
final class AtacStopAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "AtacStopAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 12, height: 12)
        centerOffset = .zero
        canShowCallout = true
        displayPriority = .defaultLow

        let dot = UIView(frame: bounds)
        dot.backgroundColor = .systemOrange
        dot.layer.cornerRadius = bounds.width / 2
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = UIColor.white.cgColor
        addSubview(dot)
    }
}
