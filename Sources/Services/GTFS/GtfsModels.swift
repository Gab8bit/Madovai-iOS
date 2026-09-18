struct GtfsStop: Hashable {
    let stopId: String
    let stopName: String
    let stopNameLower: String
    let stopLat: Double
    let stopLon: Double
    /// True for a stop from Cotral's rail feed (GTFS_FERRO) rather than its
    /// bus feed (GTFS_COTRAL) — used only for display (e.g. train vs bus
    /// icon); `stopId` itself is never namespaced, since it must stay the
    /// raw code Cotral's live PIV.do endpoint expects.
    let isRail: Bool
}

struct GtfsRoute: Hashable {
    /// Namespaced ("F:" prefix for rail) so bus and rail route ids can
    /// never collide once merged — route ids are purely an internal lookup
    /// key here, never sent to any Cotral API, so namespacing them is safe.
    let routeId: String
    let routeShortName: String
    let routeLongName: String
    let isRail: Bool
}
