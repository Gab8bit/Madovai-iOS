import Foundation

/// Pole lookup, GTFS-only — mirrors the *primary* path of the reference
/// server's `polesService.ts` (which itself only falls back to a live
/// Cotral call when GTFS has literally nothing for the area, an edge case
/// this app doesn't attempt to cover; GTFS has full regional coverage).
@MainActor
final class PolesRepository {
    private let gtfsStore: GTFSStore

    init(gtfsStore: GTFSStore) {
        self.gtfsStore = gtfsStore
    }

    func polesNear(latitude: Double, longitude: Double, range: Double = Config.nearbyPolesRangeDegrees) -> [Pole] {
        gtfsStore.findStopsByPosition(latitude: latitude, longitude: longitude, range: range).map(mapGtfsStopToPole)
    }

    func poles(in bounds: ViewportBounds) -> [Pole] {
        gtfsStore.findStopsInRegion(minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon)
            .map(mapGtfsStopToPole)
    }

    func poles(stopCode: String) -> [Pole] {
        guard let gtfsStop = gtfsStore.findStopById(stopCode) else { return [] }
        let nearby = gtfsStore.findStopsByPosition(latitude: gtfsStop.stopLat, longitude: gtfsStop.stopLon, range: 0.003)
        return nearby.isEmpty ? [mapGtfsStopToPole(gtfsStop)] : nearby.map(mapGtfsStopToPole)
    }

    /// All poles for a matched stop-search result, or all stops served by a
    /// matched line — used by the search bar.
    func poles(for stops: [GtfsStop]) -> [Pole] {
        stops.map(mapGtfsStopToPole)
    }

    func pole(for stop: GtfsStop) -> Pole {
        mapGtfsStopToPole(stop)
    }

    private func mapGtfsStopToPole(_ stop: GtfsStop) -> Pole {
        let stopRoutes = gtfsStore.getRoutesForStop(stop.stopId)
        let destinations = gtfsStore.getDestinationsFromRoutes(stopRoutes)
        return Pole(
            codicePalina: stop.stopId,
            codiceStop: stop.stopId,
            nomePalina: stop.stopName,
            nomeStop: stop.stopName,
            localita: GTFSTextUtils.extractLocalityFromStopName(stop.stopName),
            coordX: stop.stopLat,
            coordY: stop.stopLon,
            destinazioni: destinations.isEmpty ? nil : destinations,
            isCotral: stopRoutes.isEmpty ? nil : 1,
            isTreno: stop.isRail
        )
    }
}
