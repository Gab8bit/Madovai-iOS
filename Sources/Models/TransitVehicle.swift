import CoreLocation

/// A single moving vehicle shown on the map, regardless of which source it
/// came from. Cotral and Atac/Roma TPL have very different visibility
/// guarantees (see `VisibilityScope`) — the UI must never imply they're
/// equivalent.
struct TransitVehicle: Identifiable, Hashable {
    enum VisibilityScope: Hashable {
        /// Atac/Roma TPL: one GTFS-Realtime call returns every active
        /// vehicle across the whole network.
        case fullFleet
        /// Cotral: only vehicles found by querying transits at poles
        /// currently visible on screen — never the full regional fleet.
        case visibleAreaOnly
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let bearing: Double?
    /// Line id — for Atac this is the GTFS `route_id` (used to filter the
    /// map to just this line); for Cotral it's the `percorso` code from the
    /// transit that surfaced this vehicle. Namespaced consistently with
    /// however the source itself keys routes (Atac routes are already
    /// "F:"-prefixed for rail upstream — no double-namespacing needed here).
    let routeId: String?
    let routeLabel: String?
    let kind: TransitVehicleKind
    let transitOperator: TransitOperator
    let scope: VisibilityScope
    /// Seconds of delay, if a realtime source reported one (positive = late).
    let delaySeconds: Int?
    /// Which specific run this vehicle is on right now — used to look up
    /// its full stop-by-stop schedule (Atac only; see `AtacRealtimeService`).
    let tripId: String?

    static func == (lhs: TransitVehicle, rhs: TransitVehicle) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
