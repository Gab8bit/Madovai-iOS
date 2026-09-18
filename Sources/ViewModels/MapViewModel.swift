import CoreLocation
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var poles: [Pole] = []
    @Published private(set) var state: NetworkState = .idle

    @Published var searchText: String = ""
    @Published private(set) var stopResults: [SearchStopResult] = []
    @Published private(set) var routeResults: [SearchRouteResult] = []

    /// Set to request the map recenter on a coordinate (e.g. after jumping
    /// to a searched stop/line); the map view consumes and clears it.
    @Published var pendingCenter: CLLocationCoordinate2D?

    private let gtfsStore: GTFSStore
    private let atacGtfsStore: AtacGtfsStore
    private let polesRepository: PolesRepository

    init(gtfsStore: GTFSStore, atacGtfsStore: AtacGtfsStore, polesRepository: PolesRepository) {
        self.gtfsStore = gtfsStore
        self.atacGtfsStore = atacGtfsStore
        self.polesRepository = polesRepository
    }

    /// Poles always reflect whatever's currently visible on the map —
    /// called whenever the (debounced) viewport settles, including the
    /// very first layout and after recentering on a search result.
    func updateViewport(_ bounds: ViewportBounds) {
        let result = polesRepository.poles(in: bounds)
        poles = result
        state = result.isEmpty ? .empty : .loaded
    }

    /// Direct search over stop/station names and line numbers/names, across
    /// *both* Cotral and Atac/Roma TPL — more precise than a locality search
    /// when you already know where you're going or which line you want.
    func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            stopResults = []
            routeResults = []
            return
        }
        stopResults = gtfsStore.searchStops(query: query).map(SearchStopResult.cotral)
            + atacGtfsStore.searchStops(query: query).map(SearchStopResult.atac)
        routeResults = gtfsStore.searchRoutes(query: query).map(SearchRouteResult.cotral)
            + atacGtfsStore.searchRoutes(query: query).map(SearchRouteResult.atac)
    }

    func clearSearch() {
        searchText = ""
        stopResults = []
        routeResults = []
    }

    /// Jumps the map to a searched Cotral stop/station and returns the
    /// corresponding pole so the caller can open its detail sheet directly.
    /// Poles themselves refresh via the viewport pipeline once the map
    /// finishes recentering.
    @discardableResult
    func jumpTo(stop: GtfsStop) -> Pole {
        clearSearch()
        let pole = polesRepository.pole(for: stop)
        if let coordinate = pole.coordinate {
            pendingCenter = coordinate
        }
        return pole
    }

    /// Centers the map on a searched Atac/Roma TPL stop — the caller opens
    /// its detail sheet directly, since Atac stops aren't Cotral `Pole`s.
    func centerOn(atacStop stop: AtacStop) {
        clearSearch()
        pendingCenter = stop.coordinate
    }

    /// Jumps to a searched Cotral line: shows all of its stops as poles on
    /// the map immediately (not waiting for the viewport pipeline, since a
    /// long regional line's stops can easily fall outside the centroid's
    /// eventual viewport), centered on their centroid — an approximation,
    /// not a true bounding-box fit.
    func jumpTo(route: GtfsRoute) {
        clearSearch()
        let stops = gtfsStore.stopsForRoute(route.routeId)
        guard !stops.isEmpty else {
            state = .error("Nessuna fermata trovata per la linea \"\(route.routeShortName)\".")
            return
        }
        poles = polesRepository.poles(for: stops)
        state = .loaded
        let averageLatitude = stops.map(\.stopLat).reduce(0, +) / Double(stops.count)
        let averageLongitude = stops.map(\.stopLon).reduce(0, +) / Double(stops.count)
        pendingCenter = CLLocationCoordinate2D(latitude: averageLatitude, longitude: averageLongitude)
    }

    /// Centers the map on a searched Atac/Roma TPL line's shape centroid.
    /// The caller (ContentView) sets the actual line focus on success, so
    /// the same filtering used when tapping a vehicle kicks in here too.
    @discardableResult
    func jumpTo(atacRoute route: AtacRoute) -> Bool {
        clearSearch()
        let coordinates = atacGtfsStore.shapes(forRouteId: route.routeId).flatMap(\.coordinates)
        guard !coordinates.isEmpty else {
            state = .error("Nessun percorso trovato per la linea \"\(route.routeShortName)\".")
            return false
        }
        let averageLatitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let averageLongitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        pendingCenter = CLLocationCoordinate2D(latitude: averageLatitude, longitude: averageLongitude)
        return true
    }

    func centerOn(_ pole: Pole) {
        guard let coordinate = pole.coordinate else { return }
        pendingCenter = coordinate
    }
}
