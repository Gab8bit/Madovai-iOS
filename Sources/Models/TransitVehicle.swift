import CoreLocation

/// A moving vehicle on the map, from either network. Atac/Roma TPL comes from
/// one call covering the whole fleet; Cotral only from the poles currently
/// visible — the UI must never imply the two are equivalent.
struct TransitVehicle: Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let bearing: Double?
    /// Atac: GTFS route id (used to focus the map on the line). Cotral: the
    /// run's `percorso` (an ASTRAL route code like "RL_PSP-CC" for trains).
    let routeId: String?
    let routeLabel: String?
    let kind: TransitVehicleKind
    let transitOperator: TransitOperator
    /// Positive = late; nil when no reliable figure exists.
    let delaySeconds: Int?
    /// Atac: the current run, for its stop-by-stop timetable (`atac-trip`).
    let tripId: String?
    let headsign: String?
    /// Cotral vehicle code (e.g. "T395").
    let vehicleCode: String?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var isCotral: Bool { transitOperator == .cotral }

    /// Short text drawn inside the map badge (≤ 3 characters), else nil (icon).
    var badgeLabel: String? {
        guard let label = routeLabel, !label.isEmpty, label.count <= 3, CotralTrainRoute(rawValue: label) == nil else { return nil }
        return label
    }

    /// "Metro A", "Metromare", "211"…
    var lineName: String {
        if let routeId, let train = CotralTrainRoute(rawValue: routeId) { return train.lineName }
        if let label = routeLabel, let metro = AtacMetroLine(routeShortName: label) { return metro.friendlyName }
        return routeLabel ?? "—"
    }
}

/// Rome's 4 metro lines: the feed leaves their long names blank, so the
/// names are hand-written (the backend's `displayName` does the same for
/// routes; vehicles only carry the bare route label).
enum AtacMetroLine: String, CaseIterable {
    case a = "MEA"
    case b = "MEB"
    case b1 = "MEB1"
    case c = "MEC"

    init?(routeShortName: String) {
        self.init(rawValue: routeShortName.uppercased())
    }

    var friendlyName: String {
        switch self {
        case .a: return "Metro A"
        case .b: return "Metro B"
        case .b1: return "Metro B1"
        case .c: return "Metro C"
        }
    }
}
