import CoreLocation
import Foundation

/// An Atac / Roma TPL stop (one platform: a station usually has one per
/// direction). The stored property names are the pre-2.0 ones on purpose:
/// favorites saved by older versions decode unchanged.
struct AtacStop: Codable, Hashable, Identifiable {
    let stopId: String
    let stopName: String
    let lat: Double
    let lon: Double
    /// Where vehicles from this platform head (from `atac-stop`/`line`),
    /// used to label the direction picker. Not always known.
    var headsign: String? = nil

    var id: String { stopId }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    init(stopId: String, stopName: String, lat: Double, lon: Double, headsign: String? = nil) {
        self.stopId = stopId
        self.stopName = stopName
        self.lat = lat
        self.lon = lon
        self.headsign = headsign
    }
}

/// One physical station's platforms, grouped by name.
struct AtacStopGroup: Identifiable, Hashable {
    let name: String
    let stops: [AtacStop]
    /// The line the station was opened from, if any (direction labels and
    /// arrivals are then about that line).
    var routeId: String? = nil

    var id: String { "\(name)|\(stops.first?.stopId ?? "")" }

    /// Representative platform for a single map pin.
    var anchor: AtacStop { stops[0] }
}

/// Groups same-name platforms into stations, keeping every platform (each
/// one has its own real-time arrivals; collapsing them would throw a whole
/// direction away). Order of first appearance is preserved; platforms are
/// sorted by id for a deterministic anchor.
func groupedStopsByName(_ stops: [AtacStop]) -> [AtacStopGroup] {
    var order: [String] = []
    var groups: [String: [AtacStop]] = [:]
    for stop in stops {
        let key = stop.stopName.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { continue }
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(stop)
    }
    return order.map { name in
        AtacStopGroup(name: name, stops: (groups[name] ?? []).sorted { $0.stopId < $1.stopId })
    }
}

extension Pole {
    /// A Cotral pole/station built from a static stop (stops/search/line
    /// endpoints). `codicePalina` is the GTFS stop id, which is also what
    /// `cotral-transits`/`rail`/`pole` expect — and what favorites saved by
    /// earlier versions already used, so they keep matching.
    init(cotralId id: String, name: String, locality: String?, lat: Double?, lon: Double?, rail: Bool) {
        self.init(
            codicePalina: id,
            codiceStop: id,
            nomePalina: name,
            nomeStop: name,
            localita: locality ?? StopText.locality(name),
            coordX: lat,
            coordY: lon,
            isTreno: rail
        )
    }

    /// PIV.do's own pole info is often sparser than the static one: keep
    /// whichever value each field already has. The code always stays the
    /// static one (PIV.do's `codice` is another id namespace; letting it win
    /// once produced duplicate favorites).
    func merged(with info: CotralPoleInfo) -> Pole {
        var copy = self
        copy.nomePalina = info.name.nonEmpty ?? nomePalina
        copy.nomeStop = info.stopName.nonEmpty ?? nomeStop
        copy.localita = info.locality.nonEmpty ?? localita
        copy.comune = info.comune.nonEmpty ?? comune
        if let lat = info.lat, let lon = info.lon, !(lat == 0 && lon == 0) {
            copy.coordX = lat
            copy.coordY = lon
        }
        return copy
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// A line as the backend describes it (`search`, `lines`, `line`).
struct RouteInfo: Codable, Hashable, Identifiable {
    /// "atac" or "cotral".
    let source: String
    /// Atac route id ("211", "MEA") or Cotral GTFS route id ("F:ROMALIDO" for rail).
    let routeId: String
    let shortName: String
    let longName: String
    /// Ready to show ("Metro A" for metro lines).
    let displayName: String
    let kind: TransitVehicleKind
    let transitOperator: TransitOperator
    /// "E27439" (no "#"), when the feed sets one.
    let colorHex: String?
    let rail: Bool

    var id: String { "\(source):\(routeId)" }
    var isAtac: Bool { source == "atac" }
    var isCotral: Bool { source == "cotral" }

    enum CodingKeys: String, CodingKey {
        case source, shortName, longName, displayName, kind, rail
        case routeId = "id"
        case transitOperator = "operator"
        case colorHex = "color"
    }

    init(source: String, routeId: String, shortName: String, longName: String, displayName: String,
         kind: TransitVehicleKind, transitOperator: TransitOperator, colorHex: String?, rail: Bool) {
        self.source = source
        self.routeId = routeId
        self.shortName = shortName
        self.longName = longName
        self.displayName = displayName
        self.kind = kind
        self.transitOperator = transitOperator
        self.colorHex = colorHex
        self.rail = rail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(String.self, forKey: .source)) ?? "atac"
        routeId = try c.decode(String.self, forKey: .routeId)
        shortName = (try? c.decodeIfPresent(String.self, forKey: .shortName)) ?? routeId
        longName = (try? c.decodeIfPresent(String.self, forKey: .longName)) ?? ""
        let display: String? = try? c.decodeIfPresent(String.self, forKey: .displayName)
        displayName = display.nonEmpty ?? shortName
        kind = (try? c.decodeIfPresent(TransitVehicleKind.self, forKey: .kind)) ?? .bus
        rail = (try? c.decodeIfPresent(Bool.self, forKey: .rail)) ?? false
        transitOperator = (try? c.decodeIfPresent(TransitOperator.self, forKey: .transitOperator)) ?? (source == "cotral" ? .cotral : .atac)
        let color: String? = try? c.decodeIfPresent(String.self, forKey: .colorHex)
        colorHex = color.nonEmpty
    }

    var iconName: String {
        isCotral ? (rail ? "tram.fill" : "bus") : kind.sfSymbolName
    }

    var operatorLabel: String {
        isCotral ? (rail ? "Cotral · treno" : "Cotral") : transitOperator.rawValue
    }

    var isMetro: Bool { kind == .metro || AtacMetroLine(routeShortName: shortName) != nil }

    /// What a rider recognises: "Metro A", the bus/tram number ("64"), the
    /// rail line's name ("METROMARE"). The backend's `displayName` is the
    /// long route description for most Atac lines, which hid the number.
    var title: String {
        if isAtac {
            if isMetro { return AtacMetroLine(routeShortName: shortName)?.friendlyName ?? displayName }
            return shortName
        }
        return rail ? (longName.nonEmpty ?? displayName) : shortName
    }

    /// Long description under the title, unless it just repeats it.
    var subtitleName: String? {
        guard let long = longName.nonEmpty, long.caseInsensitiveCompare(title) != .orderedSame else { return nil }
        return long
    }
}

/// A stop as returned by `search` (either network).
struct SearchStop: Codable, Hashable, Identifiable {
    let source: String
    let stopId: String
    let name: String
    let lat: Double
    let lon: Double
    let rail: Bool
    /// Atac metro station (no per-stop live data → not usable for reminders).
    let metro: Bool

    var id: String { "\(source):\(stopId)" }
    var isCotral: Bool { source == "cotral" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    enum CodingKeys: String, CodingKey { case source, name, lat, lon, rail, metro, stopId = "id" }

    init(source: String, stopId: String, name: String, lat: Double, lon: Double, rail: Bool, metro: Bool) {
        self.source = source
        self.stopId = stopId
        self.name = name
        self.lat = lat
        self.lon = lon
        self.rail = rail
        self.metro = metro
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(String.self, forKey: .source)) ?? "atac"
        stopId = try c.decode(String.self, forKey: .stopId)
        name = (try? c.decode(String.self, forKey: .name)) ?? stopId
        lat = (try? c.decode(Double.self, forKey: .lat)) ?? 0
        lon = (try? c.decode(Double.self, forKey: .lon)) ?? 0
        rail = (try? c.decodeIfPresent(Bool.self, forKey: .rail)) ?? false
        metro = (try? c.decodeIfPresent(Bool.self, forKey: .metro)) ?? false
    }

    var iconName: String { isCotral ? (rail ? "tram.fill" : "bus") : "mappin.circle" }
    var subtitle: String { isCotral ? (rail ? "Cotral · treno" : "Cotral") : "Atac / Roma TPL" }

    var asPole: Pole { Pole(cotralId: stopId, name: name, locality: nil, lat: lat, lon: lon, rail: rail) }
    var asAtacStop: AtacStop { AtacStop(stopId: stopId, stopName: name, lat: lat, lon: lon) }
}

/// A drawable line shape, decoded once off the main thread.
struct MapShape: Identifiable, Hashable {
    let id: String
    let routeId: String
    let kind: TransitVehicleKind
    let colorHex: String?
    let coordinates: [CLLocationCoordinate2D]

    static func == (lhs: MapShape, rhs: MapShape) -> Bool {
        lhs.id == rhs.id && lhs.routeId == rhs.routeId && lhs.colorHex == rhs.colorHex && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(routeId)
    }
}
