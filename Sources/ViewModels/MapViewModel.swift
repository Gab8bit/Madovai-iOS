import CoreLocation
import Foundation

/// A one-shot instruction for the map camera. Each request has its own id so
/// the map applies it exactly once, even if SwiftUI re-renders many times.
struct CameraRequest: Equatable {
    enum Target: Equatable {
        /// Centre on a point showing about `meters` across.
        case center(CLLocationCoordinate2D, meters: Double)
        /// Fit all points, not zooming in past `maxZoom`.
        case fit([CLLocationCoordinate2D], maxZoom: Double)
    }

    let id = UUID()
    let target: Target
}

/// The line currently isolated on the map (its shape, stops and vehicles
/// only), set by tapping a vehicle or picking a line in search. It stays
/// until the user taps "Reset" — closing a sheet doesn't clear it.
struct LineFocus: Equatable {
    enum Kind: Equatable { case loading, atac, cotral, unknown }

    /// Atac route id, or a Cotral `percorso` (ASTRAL route code) for a
    /// tapped Cotral vehicle — compared against `TransitVehicle.routeId`.
    let routeId: String
    var kind: Kind
    var route: RouteInfo?
    var stops: [AtacStop] = []
    var shapes: [MapShape] = []
}

/// Everything the map shows besides live vehicles: stops/poles and line
/// shapes for the settled viewport, the focused line, and the loading/error
/// state behind the banners.
@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var viewport: MapViewport?
    @Published private(set) var poles: [Pole] = []
    @Published private(set) var atacStops: [AtacStop] = []
    @Published private(set) var viewportShapes: [MapShape] = []
    /// Poles of a Cotral line picked in search (may lie outside the
    /// viewport); replaced by the normal viewport poles on the next load.
    @Published private(set) var routePoles: [Pole]?
    /// True only while a load is slower than `Config.slowRequestHintDelay`.
    @Published private(set) var isLoading = false
    @Published private(set) var dataError: APIError?
    @Published private(set) var linesVisible = true
    @Published private(set) var focus: LineFocus?
    /// "Nessun percorso trovato…" and similar, shown until dismissed.
    @Published var notice: String?
    @Published var cameraRequest: CameraRequest?

    private let api: MadovaiAPI
    private let linesStore: LinesStore
    private weak var connectivity: ConnectivityMonitor?
    private var loadTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?

    init(api: MadovaiAPI = .shared, linesStore: LinesStore, connectivity: ConnectivityMonitor? = nil) {
        self.api = api
        self.linesStore = linesStore
        self.connectivity = connectivity
    }

    func attach(connectivity: ConnectivityMonitor) {
        self.connectivity = connectivity
    }

    var isZoomedOutForData: Bool {
        guard let viewport else { return false }
        return viewport.zoom < Config.minDataZoom
    }

    // MARK: - Viewport

    func viewportSettled(_ newViewport: MapViewport) {
        guard newViewport != viewport else { return }
        viewport = newViewport
        load()
    }

    func reload() {
        load()
    }

    func toggleLines() {
        linesVisible.toggle()
        load()
    }

    private func load() {
        loadTask?.cancel()
        guard let viewport else { return }
        guard viewport.zoom >= Config.minDataZoom else {
            // A regional view would mean thousands of markers: show none,
            // and say why (the map overlay hints "Avvicina la mappa…").
            poles = []
            atacStops = []
            viewportShapes = []
            dataError = nil
            isLoading = false
            return
        }
        let bounds = viewport.bounds.padded
        let wantShapes = linesVisible
        loadTask = Task { [weak self] in
            guard let self else { return }
            let hint = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Config.slowRequestHintDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.isLoading = true
            }
            defer {
                hint.cancel()
                if !Task.isCancelled { isLoading = false }
            }
            do {
                async let stopsResult = api.stops(in: bounds)
                async let shapesResult: [MapShape] = wantShapes ? api.shapes(in: bounds) : []
                let (stops, shapes) = try await (stopsResult, shapesResult)
                guard !Task.isCancelled else { return }
                poles = stops.poles
                atacStops = stops.atacStops
                viewportShapes = shapes
                routePoles = nil
                dataError = nil
                connectivity?.reportSuccess()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                // Keep whatever is already on the map; the banner explains
                // it may be stale and offers a retry.
                dataError = error as? APIError ?? .offline
                connectivity?.report(error)
            }
        }
    }

    // MARK: - Line focus

    /// Isolates a line on the map. Accepts an Atac route id or a Cotral
    /// vehicle's `percorso` (rail direction code, mapped to the GTFS rail
    /// line by its short name).
    func focus(routeId: String?) {
        focusTask?.cancel()
        guard let routeId, !routeId.isEmpty else {
            focus = nil
            return
        }
        if focus?.routeId == routeId, focus?.kind != .unknown { return }
        focus = LineFocus(routeId: routeId, kind: .loading)
        focusTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await resolveFocus(routeId: routeId)
            guard !Task.isCancelled, focus?.routeId == routeId else { return }
            focus = resolved
        }
    }

    func clearFocus() {
        focusTask?.cancel()
        focus = nil
    }

    private func resolveFocus(routeId: String) async -> LineFocus {
        if let train = CotralTrainRoute(rawValue: routeId) {
            guard let lines = await linesStore.load(),
                  let rail = lines.cotralRail.first(where: { $0.shortName.uppercased() == train.gtfsRouteShortName }),
                  let detail = try? await api.line(source: "cotral", id: rail.routeId)
            else { return LineFocus(routeId: routeId, kind: .unknown) }
            return LineFocus(routeId: routeId, kind: .cotral, route: detail.route, stops: [], shapes: detail.shapes)
        }
        do {
            let detail = try await api.line(source: "atac", id: routeId)
            return LineFocus(routeId: routeId, kind: .atac, route: detail.route, stops: detail.stops.map(\.asAtacStop), shapes: detail.shapes)
        } catch {
            // A Cotral bus `percorso` has no shape: the focus still filters
            // vehicles to the line, it just can't draw it.
            return LineFocus(routeId: routeId, kind: .unknown)
        }
    }

    // MARK: - Search selections

    /// A Cotral line from search: show all its stops right away (they may
    /// fall outside the eventual viewport) and fit the camera on them.
    /// Returns false (with a notice) when nothing could be shown.
    func showCotralRoute(_ route: RouteInfo) async -> Bool {
        notice = nil
        do {
            let detail = try await api.line(source: "cotral", id: route.routeId)
            guard !detail.stops.isEmpty else {
                notice = "Nessuna fermata trovata per la linea \"\(route.shortName)\"."
                return false
            }
            clearFocus()
            routePoles = detail.stops.map {
                Pole(cotralId: $0.id, name: $0.name, locality: nil, lat: $0.lat, lon: $0.lon, rail: route.rail)
            }
            cameraRequest = CameraRequest(target: .fit(detail.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }, maxZoom: 14))
            return true
        } catch {
            notice = error.userMessage
            return false
        }
    }

    /// An Atac line from search: fit its shape and focus it.
    func showAtacRoute(_ route: RouteInfo) async {
        notice = nil
        focusTask?.cancel()
        do {
            let detail = try await api.line(source: "atac", id: route.routeId)
            let points = detail.shapes.flatMap(\.coordinates)
            let fitPoints = points.isEmpty ? detail.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } : points
            guard !fitPoints.isEmpty else {
                notice = "Nessun percorso trovato per la linea \"\(route.title)\"."
                return
            }
            cameraRequest = CameraRequest(target: .fit(fitPoints, maxZoom: 15))
            focus = LineFocus(routeId: route.routeId, kind: .atac, route: detail.route, stops: detail.stops.map(\.asAtacStop), shapes: detail.shapes)
        } catch {
            notice = error.userMessage
        }
    }

    func center(on coordinate: CLLocationCoordinate2D, meters: Double = 900) {
        cameraRequest = CameraRequest(target: .center(coordinate, meters: meters))
    }

    // MARK: - What the map draws

    var shownPoles: [Pole] {
        focus == nil ? (routePoles ?? poles) : []
    }

    var shownAtacStops: [AtacStop] {
        if let focus {
            return focus.kind == .atac ? groupedStopsByName(focus.stops).map(\.anchor) : []
        }
        return groupedStopsByName(atacStops).map(\.anchor)
    }

    var shownShapes: [MapShape] {
        if let focus { return focus.shapes }
        return linesVisible ? viewportShapes : []
    }

    /// Vehicles to draw: the focused line's at any zoom, otherwise those in
    /// the padded viewport above `Config.minVehicleZoom`. Pure, for tests.
    nonisolated static func visibleVehicles(_ all: [TransitVehicle], focusRouteId: String?, viewport: MapViewport?) -> [TransitVehicle] {
        if let focusRouteId {
            return all.filter { $0.routeId == focusRouteId }
        }
        guard let viewport, viewport.zoom >= Config.minVehicleZoom else { return [] }
        let box = viewport.bounds.padded
        return all.filter { box.contains($0.coordinate) }
    }
}
