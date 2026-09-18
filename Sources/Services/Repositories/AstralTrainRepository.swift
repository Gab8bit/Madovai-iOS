import Foundation

/// Primary source for Cotral rail schedules/delays — see `AstralTrainClient`
/// for why (PIV.do can silently omit a real train). Resolves a GTFS rail
/// station to ASTRAL's own stop code by name (there's no shared id space —
/// confirmed ASTRAL's codes differ from PIV.do's even where they look
/// alike), caching each line+direction's station list after first fetch
/// (only 8 `CotralTrainRoute` values total, tiny payloads, no need to
/// expire within a session).
@MainActor
final class AstralTrainRepository {
    private let client: AstralTrainClient
    private var stationsCache: [String: [AstralStation]] = [:]

    init(client: AstralTrainClient = .shared) {
        self.client = client
    }

    /// All stations for one line+direction, in physical order — used both
    /// internally for name-matching and by `CotralVehicleDetailSheet` to
    /// show a full per-station rundown for a tapped vehicle's line.
    func stations(for route: CotralTrainRoute) async throws -> [AstralStation] {
        if let cached = stationsCache[route.rawValue] { return cached }
        let stations = try await client.fetchStations(percorso: route.rawValue).sorted { $0.ordine < $1.ordine }
        stationsCache[route.rawValue] = stations
        return stations
    }

    /// Today's remaining departures for `stationName` in `route`'s
    /// direction — `nil` when that station can't be matched at all for this
    /// route (mirrors the old widget-tier's "just leaves it nil, caller
    /// falls through to the next tier" behavior), not an error.
    func departures(for route: CotralTrainRoute, stationName: String) async throws -> AstralScheduleDirection? {
        guard let fermata = try await fermataCode(for: route, stationName: stationName) else { return nil }
        let transits = try await client.fetchTransits(percorso: route.rawValue, fermata: fermata)
        let entries = transits.compactMap { dto -> AstralDeparture? in
            guard let seconds = Self.secondsFromHHMM(dto.orario) else { return nil }
            return AstralDeparture(
                id: dto.corsa,
                time: dto.orario,
                sortSeconds: seconds,
                delayMinutes: Int(dto.ritardo.trimmingCharacters(in: .whitespaces)),
                isCancelled: dto.soppressa.trimmingCharacters(in: .whitespaces).uppercased() == "Y",
                isReplacementBus: dto.busSostitutivo.trimmingCharacters(in: .whitespaces).uppercased() == "Y"
            )
        }
        return AstralScheduleDirection(destination: route.destinationName, entries: entries)
    }

    /// Exact match first; GTFS and ASTRAL don't always spell a station the
    /// same way (same gotcha the old cotralspa.it-widget matching had, e.g.
    /// GTFS "Acilia Sud" vs a differently-suffixed ASTRAL name) — a
    /// substring match in either direction recovers those without being so
    /// loose it could cross-match two different stations.
    private func fermataCode(for route: CotralTrainRoute, stationName: String) async throws -> String? {
        let target = stationName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !target.isEmpty else { return nil }
        let allStations = try await stations(for: route)

        if let exact = allStations.first(where: { $0.nomeFermata.trimmingCharacters(in: .whitespaces).lowercased() == target }) {
            return exact.codice
        }
        return allStations.first(where: { station in
            let name = station.nomeFermata.trimmingCharacters(in: .whitespaces).lowercased()
            return name.contains(target) || target.contains(name)
        })?.codice
    }

    private static func secondsFromHHMM(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 3600 + minutes * 60
    }
}
