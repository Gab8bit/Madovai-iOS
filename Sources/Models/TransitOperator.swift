/// Which agency a piece of data (stop, line, vehicle) belongs to. Cotral
/// covers extra-urban Lazio; Atac and Roma TPL together cover urban Rome —
/// shown together on one map but never conflated. Raw values are the
/// backend's `operator` strings.
enum TransitOperator: String, Codable, Hashable {
    case cotral = "Cotral"
    case atac = "Atac"
    case romaTpl = "Roma TPL"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransitOperator(rawValue: raw) ?? .atac
    }
}

/// Vehicle/line kind, used to pick map glyphs/colors. Raw values are the
/// backend's `kind` strings; anything unknown decodes as a bus.
enum TransitVehicleKind: String, Codable, Hashable {
    case bus
    case tram
    case metro
    case treno

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransitVehicleKind(rawValue: raw.lowercased()) ?? .bus
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
