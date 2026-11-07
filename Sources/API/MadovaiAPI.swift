import CoreLocation
import Foundation

/// Typed wrappers for every backend endpoint the app uses. All calls run off
/// the main actor and return values ready for the UI (polylines decoded,
/// DTOs mapped to app models).
struct MadovaiAPI: Sendable {
    static let shared = MadovaiAPI(client: .shared)

    let client: APIClient

    // MARK: - Server

    func health() async throws -> HealthResponse {
        var components = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/health"
        components.query = nil
        return try await client.get(absolute: components.url!)
    }

    // MARK: - Static data

    func search(_ query: String) async throws -> SearchResponse {
        try await client.get("search", query: ["q": query])
    }

    /// Cotral poles + Atac stops inside a box, nearest to its centre first.
    func stops(in bounds: ViewportBounds, cotralLimit: Int = 120, atacLimit: Int = 400) async throws -> (poles: [Pole], atacStops: [AtacStop]) {
        let response: ViewportStopsResponse = try await client.get("stops", query: Self.bboxQuery(bounds).merging([
            "cotralLimit": String(cotralLimit),
            "atacLimit": String(atacLimit),
        ]) { $1 })
        let poles = response.cotral.map {
            Pole(cotralId: $0.id, name: $0.name, locality: $0.locality, lat: $0.lat, lon: $0.lon, rail: $0.rail ?? false)
        }
        let atac = response.atac.map { AtacStop(stopId: $0.id, stopName: $0.name, lat: $0.lat, lon: $0.lon) }
        return (poles, atac)
    }

    /// Atac line shapes crossing a box.
    func shapes(in bounds: ViewportBounds, limit: Int = 150) async throws -> [MapShape] {
        let response: ShapesResponse = try await client.get("shapes", query: Self.bboxQuery(bounds).merging(["limit": String(limit)]) { $1 })
        return response.shapes.map { Self.mapShape($0, fallbackRouteId: "", kind: .bus, color: nil) }
    }

    func lines() async throws -> LinesResponse {
        try await client.get("lines")
    }

    /// `source` is "atac" or "cotral".
    func line(source: String, id: String) async throws -> LineDetail {
        let response: LineResponse = try await client.get("line", query: ["source": source, "id": id])
        let route = response.route
        let kind: TransitVehicleKind = route.isCotral ? .treno : route.kind
        let shapes = response.shapes.map { Self.mapShape($0, fallbackRouteId: route.routeId, kind: kind, color: route.colorHex, forceRoute: true) }
        return LineDetail(route: route, stops: response.stops, shapes: shapes)
    }

    /// Every platform sharing the name of `stopId` (a station's directions).
    func atacStop(id: String, route: String? = nil) async throws -> AtacStopResponse {
        try await client.get("atac-stop", query: ["id": id, "route": route])
    }

    /// Up to 6 *scheduled* (not real-time) departures from now.
    func atacSchedule(stopId: String) async throws -> [AtacArrival] {
        try await client.get("atac-schedule", query: ["stop": stopId])
    }

    func pole(id: String) async throws -> PoleResponse {
        try await client.get("pole", query: ["id": id])
    }

    func rail(stopId: String) async throws -> RailResponse {
        try await client.get("rail", query: ["stop": stopId])
    }

    // MARK: - Live data

    func cotralTransits(pole: String) async throws -> TransitsResponse {
        try await client.get("cotral-transits", query: ["pole": pole])
    }

    func cotralVehicle(code: String) async throws -> CLLocationCoordinate2D? {
        let response: VehiclePositionResponse = try await client.get("cotral-vehicle", query: ["code": code])
        guard let lat = response.lat, let lon = response.lon else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return coordinate.isValidForMap ? coordinate : nil
    }

    /// Trackable Cotral vehicles passing through the given poles (max 15).
    func cotralVehicles(poles: [String]) async throws -> [TransitVehicle] {
        let codes = Array(poles.prefix(Config.cotralViewportPoleQueryLimit))
        guard !codes.isEmpty else { return [] }
        let response: CotralVehiclesResponse = try await client.get("cotral-vehicles", query: ["poles": codes.joined(separator: ",")])
        return response.vehicles.compactMap { v in
            let coordinate = CLLocationCoordinate2D(latitude: v.lat, longitude: v.lon)
            guard coordinate.isValidForMap else { return nil }
            return TransitVehicle(
                id: v.id, latitude: v.lat, longitude: v.lon, bearing: nil,
                routeId: v.routeId, routeLabel: v.routeLabel, kind: v.kind ?? .bus, transitOperator: .cotral,
                delaySeconds: v.delaySeconds, tripId: v.tripId, headsign: nil, vehicleCode: v.code
            )
        }
    }

    func astralLine(route: String) async throws -> AstralLineResponse {
        try await client.get("astral-line", query: ["route": route])
    }

    func atacVehicles() async throws -> (vehicles: [TransitVehicle], updated: Date?) {
        let response: AtacVehiclesResponse = try await client.get("atac-vehicles")
        let vehicles = response.vehicles.compactMap { v -> TransitVehicle? in
            let coordinate = CLLocationCoordinate2D(latitude: v.lat, longitude: v.lon)
            guard coordinate.isValidForMap else { return nil }
            return TransitVehicle(
                id: v.id, latitude: v.lat, longitude: v.lon, bearing: v.bearing,
                routeId: v.routeId, routeLabel: v.routeLabel, kind: v.kind ?? .bus, transitOperator: v.operator ?? .atac,
                delaySeconds: nil, tripId: v.tripId, headsign: v.headsign.nonEmpty, vehicleCode: nil
            )
        }
        return (vehicles, response.updated.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    /// Real-time arrivals for any number of stops (chunked to the
    /// backend's 150-stop limit), each list sorted soonest first.
    func atacLive(stopIds: [String]) async throws -> [String: [AtacArrival]] {
        let unique = Array(NSOrderedSet(array: stopIds).compactMap { $0 as? String })
        guard !unique.isEmpty else { return [:] }
        let chunks = stride(from: 0, to: unique.count, by: Config.atacLiveStopLimit).map {
            Array(unique[$0..<min($0 + Config.atacLiveStopLimit, unique.count)])
        }
        var merged: [String: [AtacArrival]] = [:]
        try await withThrowingTaskGroup(of: [String: [AtacArrival]].self) { group in
            for chunk in chunks {
                group.addTask {
                    let response: AtacLiveResponse = try await client.get("atac-live", query: ["stops": chunk.joined(separator: ",")])
                    return response.stops
                }
            }
            for try await part in group {
                merged.merge(part) { $1 }
            }
        }
        return merged.mapValues { $0.sorted { $0.ts < $1.ts } }
    }

    func atacTrip(tripId: String) async throws -> AtacTripResponse {
        try await client.get("atac-trip", query: ["trip": tripId])
    }

    // MARK: - Helpers

    static func bboxQuery(_ b: ViewportBounds) -> [String: String?] {
        [
            "minLat": String(format: "%.5f", b.minLat),
            "minLon": String(format: "%.5f", b.minLon),
            "maxLat": String(format: "%.5f", b.maxLat),
            "maxLon": String(format: "%.5f", b.maxLon),
        ]
    }

    static func mapShape(_ dto: ShapeDTO, fallbackRouteId: String, kind: TransitVehicleKind, color: String?, forceRoute: Bool = false) -> MapShape {
        MapShape(
            id: dto.id,
            routeId: forceRoute ? fallbackRouteId : (dto.routeId ?? fallbackRouteId),
            kind: forceRoute ? kind : (dto.kind ?? kind),
            colorHex: (forceRoute ? color : (dto.color ?? color)).nonEmpty,
            coordinates: Polyline.decode(dto.coords)
        )
    }
}
