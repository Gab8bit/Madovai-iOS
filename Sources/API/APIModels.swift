import Foundation

// Wire shapes of the backend's JSON responses (see Madovai-Backend
// docs/API.md). Decoding is deliberately tolerant: optional fields may be
// null or missing, unknown fields are ignored. Values the UI works with
// (`Transit`, `AstralDeparture`, `RouteInfo`, `SearchStop`) live in Models/.

struct HealthResponse: Decodable {
    let ok: Bool
    let version: String?
    let gtfsReady: Bool
}

struct SearchResponse: Decodable {
    let stops: [SearchStop]
    let routes: [RouteInfo]
}

struct ViewportStopsResponse: Decodable {
    struct CotralStop: Decodable {
        let id: String
        let name: String
        let locality: String?
        let lat: Double
        let lon: Double
        let rail: Bool?
    }

    struct AtacStopDTO: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
    }

    let cotral: [CotralStop]
    let atac: [AtacStopDTO]
}

struct LinesResponse: Decodable {
    let atac: [RouteInfo]
    let cotralRail: [RouteInfo]
}

/// A stop in `line` / `atac-stop` responses.
struct LineStopDTO: Decodable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let headsign: String?

    var asAtacStop: AtacStop { AtacStop(stopId: id, stopName: name, lat: lat, lon: lon, headsign: headsign.nonEmpty) }
}

struct ShapeDTO: Decodable {
    let id: String
    let routeId: String?
    let kind: TransitVehicleKind?
    let color: String?
    let coords: String
}

struct LineResponse: Decodable {
    let route: RouteInfo
    let stops: [LineStopDTO]
    let shapes: [ShapeDTO]
}

/// `line` with its shapes already decoded into coordinates.
struct LineDetail {
    let route: RouteInfo
    let stops: [LineStopDTO]
    let shapes: [MapShape]
}

struct ShapesResponse: Decodable {
    let shapes: [ShapeDTO]
}

struct AtacStopResponse: Decodable {
    let name: String?
    let stops: [LineStopDTO]
}

/// One upcoming arrival at an Atac stop (`atac-live`, or the scheduled
/// fallback `atac-schedule`, which has no delay/cancellation fields).
struct AtacArrival: Decodable, Hashable, Identifiable {
    let tripId: String
    let routeId: String
    let routeLabel: String
    let kind: TransitVehicleKind
    /// Unix seconds.
    let ts: Int
    let delaySeconds: Int?
    let headsign: String?
    let cancelled: Bool

    var id: String { "\(tripId)|\(ts)" }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    var timeLabel: String { RomeTime.hhmm(unix: ts) }
    func minutesFromNow(now: Date = Date()) -> Int { Int(date.timeIntervalSince(now) / 60) }

    enum CodingKeys: String, CodingKey { case tripId, routeId, routeLabel, kind, ts, delaySeconds, headsign, cancelled }

    init(tripId: String, routeId: String, routeLabel: String, kind: TransitVehicleKind, ts: Int, delaySeconds: Int?, headsign: String?, cancelled: Bool) {
        self.tripId = tripId
        self.routeId = routeId
        self.routeLabel = routeLabel
        self.kind = kind
        self.ts = ts
        self.delaySeconds = delaySeconds
        self.headsign = headsign
        self.cancelled = cancelled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decode(Int.self, forKey: .ts)
        tripId = (try? c.decodeIfPresent(String.self, forKey: .tripId)) ?? "\(ts)"
        routeId = (try? c.decodeIfPresent(String.self, forKey: .routeId)) ?? ""
        routeLabel = (try? c.decodeIfPresent(String.self, forKey: .routeLabel)) ?? routeId
        kind = (try? c.decodeIfPresent(TransitVehicleKind.self, forKey: .kind)) ?? .bus
        delaySeconds = try? c.decodeIfPresent(Int.self, forKey: .delaySeconds)
        headsign = (try? c.decodeIfPresent(String.self, forKey: .headsign)).nonEmpty
        cancelled = (try? c.decodeIfPresent(Bool.self, forKey: .cancelled)) ?? false
    }
}

struct AtacLiveResponse: Decodable {
    let updated: Int?
    let stops: [String: [AtacArrival]]
}

struct PoleResponse: Decodable {
    let id: String
    let name: String?
    let locality: String?
    let lat: Double?
    let lon: Double?
    let rail: Bool?
    let trainRoutes: [String]?
}

struct RailResponse: Decodable {
    /// "astral" (real-time), "gtfs" (timetable only) or "none".
    let source: String
    let directions: [AstralScheduleDirection]
}

/// PIV.do's own description of a pole (`cotral-transits` → `pole`).
struct CotralPoleInfo: Decodable, Hashable {
    let code: String?
    let name: String?
    let stopName: String?
    let locality: String?
    let comune: String?
    let lat: Double?
    let lon: Double?
}

struct TransitsResponse: Decodable {
    let pole: CotralPoleInfo?
    let transits: [Transit]
}

struct VehiclePositionResponse: Decodable {
    let lat: Double?
    let lon: Double?
}

struct CotralVehiclesResponse: Decodable {
    struct Vehicle: Decodable {
        let id: String
        let code: String?
        let lat: Double
        let lon: Double
        let routeId: String?
        let routeLabel: String?
        let kind: TransitVehicleKind?
        let delaySeconds: Int?
        let tripId: String?
    }

    let vehicles: [Vehicle]
}

struct AstralLineResponse: Decodable {
    struct Station: Decodable, Identifiable, Hashable {
        let name: String
        let code: String?
        let order: Int?
        let next: AstralDeparture?

        var id: String { code ?? name }
    }

    let route: String
    let directionLabel: String?
    let lineName: String?
    let stations: [Station]
}

struct AtacVehiclesResponse: Decodable {
    struct Vehicle: Decodable {
        let id: String
        let lat: Double
        let lon: Double
        let bearing: Double?
        let routeId: String?
        let routeLabel: String?
        let kind: TransitVehicleKind?
        let `operator`: TransitOperator?
        let tripId: String?
        let headsign: String?
    }

    let updated: Int?
    let vehicles: [Vehicle]
}

struct AtacTripResponse: Decodable {
    struct Stop: Decodable, Identifiable, Hashable {
        let stopId: String
        let stopName: String
        let sequence: Int
        let ts: Int
        let delaySeconds: Int?

        var id: String { "\(stopId)-\(sequence)" }
        var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    }

    let tripId: String?
    let routeId: String?
    let routeLabel: String?
    let headsign: String?
    let stops: [Stop]
}
