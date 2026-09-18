/// Which agency a piece of data (pole, line, vehicle) belongs to. Cotral
/// covers extra-urban Lazio; Atac and Roma TPL together cover urban Rome —
/// different coverage areas, different data sources, shown together on one
/// map but never conflated.
enum TransitOperator: String {
    case cotral = "Cotral"
    case atac = "Atac"
    case romaTpl = "Roma TPL"
}

/// Vehicle/line kind, used to pick map glyphs/colors. GTFS `route_type`
/// numeric codes: 0 = tram, 1 = subway/metro, 2 = rail, 3 = bus.
enum TransitVehicleKind: Int {
    case tram = 0
    case metro = 1
    case treno = 2
    case bus = 3

    init(gtfsRouteType: Int) {
        self = TransitVehicleKind(rawValue: gtfsRouteType) ?? .bus
    }

    var sfSymbolName: String {
        switch self {
        case .tram: return "tram.fill"
        case .metro: return "m.circle.fill"
        case .treno: return "tram.fill"
        case .bus: return "bus"
        }
    }
}
