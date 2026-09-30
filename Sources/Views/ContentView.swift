import CoreLocation
import MapKit
import SwiftUI

/// The app's 4 top-level sections, each its own `TabView` panel.
private enum RootTab: Hashable {
    case map, linee, preferiti, reminders
}

struct ContentView: View {
    @StateObject private var gtfsStore: GTFSStore
    @StateObject private var mapViewModel: MapViewModel
    @StateObject private var locationManager = LocationManager()
    @StateObject private var favoritesStore = FavoritesStore()
    /// A true singleton, not owned here — see `ReminderStore.shared`'s doc
    /// comment for why (the background task registration in
    /// `CotralLiveApp.init()` needs the exact same instance).
    @ObservedObject private var reminderStore = ReminderStore.shared
    @StateObject private var vehicleTracker: VehicleTracker

    @StateObject private var atacGtfsStore: AtacGtfsStore
    @StateObject private var atacViewModel: AtacViewModel
    @StateObject private var atacRealtimeService: AtacRealtimeService
    @StateObject private var viewportState = MapViewportState()
    @StateObject private var cotralViewportVehicles: CotralViewportVehicleService

    private let transitsRepository = TransitsRepository()
    private let astralTrainRepository = AstralTrainRepository()

    @State private var selectedPole: Pole?
    /// The full station (every platform sharing its name, resolved via
    /// `AtacGtfsStore.stopsSharingName(with:)`) behind whichever single
    /// `AtacStop` a map pin, search result, or vehicle tap reported —
    /// needed so `AtacStopDetailSheet` can offer its direction picker from
    /// any entry point, not just the "Linee" browser's own station list.
    @State private var selectedAtacStopGroup: AtacStopGroup?
    /// Opens the vehicle's detail sheet. Independent of `focusedRouteId`
    /// below on purpose (see its doc comment) — closing this sheet must NOT
    /// reset the focused line, only the explicit reset button does.
    @State private var selectedVehicle: TransitVehicle?
    /// "trip_selected": the line currently isolated on the map (its own
    /// shape + only its own vehicles/stops), set by tapping a vehicle or
    /// picking a line from search/the Linee browser. Persists until the
    /// user explicitly resets it — dismissing a sheet does not clear it.
    @State private var focusedRouteId: String?
    /// Set when a Cotral rail line is picked from the map search bar, to
    /// open its station/schedule list (`LineeDetailView`) — the "Linee" tab
    /// reaches the same view via its own `NavigationLink`, but there's no
    /// navigation stack here to push onto, so this is presented as a sheet
    /// instead.
    @State private var searchedCotralRoute: SearchRouteResult?
    @State private var showInfo = false
    @State private var selectedTab: RootTab = .map
    @State private var hasRequestedLocation = false
    /// Guards the map's one-time initial recenter onto the user's own
    /// location (see the `onChange` below) — a dedicated flag rather than
    /// checking `mapViewModel.poles.isEmpty`, which used to cause the same
    /// recenter to keep firing on every later location update whenever the
    /// user panned/drove somewhere with no nearby poles (poles is
    /// viewport-scoped and legitimately empty in that case), fighting any
    /// attempt to pan the map away from the user while moving.
    @State private var hasCenteredOnUserOnce = false
    @State private var hasStartedRealtimePolling = false

    init() {
        let gtfs = GTFSStore()
        let atacGtfs = AtacGtfsStore()
        let polesRepository = PolesRepository(gtfsStore: gtfs)
        _gtfsStore = StateObject(wrappedValue: gtfs)
        _atacGtfsStore = StateObject(wrappedValue: atacGtfs)
        _mapViewModel = StateObject(wrappedValue: MapViewModel(gtfsStore: gtfs, atacGtfsStore: atacGtfs, polesRepository: polesRepository))
        _vehicleTracker = StateObject(wrappedValue: VehicleTracker(repository: VehicleRepository()))

        _atacViewModel = StateObject(wrappedValue: AtacViewModel(gtfsStore: atacGtfs))
        _atacRealtimeService = StateObject(wrappedValue: AtacRealtimeService(gtfsStore: atacGtfs))
        _cotralViewportVehicles = StateObject(wrappedValue: CotralViewportVehicleService(
            transitsRepository: TransitsRepository(),
            vehicleRepository: VehicleRepository()
        ))
    }

    var body: some View {
        // Three top-level sections in a plain bottom `TabView` — per the
        // HIG's own tab bar guidance, a standard system tab bar (not a
        // hand-rolled floating panel) is what actually picks up the
        // platform's current bottom-bar material for free; hand-rolling a
        // custom bar for the same visual only fights the system anytime
        // that material changes. The map is shown immediately and stays
        // usable while both GTFS stores load in the background —
        // poles/lines/stops simply appear as each store finishes, rather
        // than blocking the whole app behind a loading screen the way this
        // used to work. `dataLoadingBanner` communicates what's still
        // missing meanwhile. Both `.task`s live at this top level, not
        // inside `mapScreen`, so the load starts regardless of which tab is
        // showing first and isn't repeated if the user switches tabs.
        TabView(selection: $selectedTab) {
            mapScreen
                .tabItem { Label("Mappa", systemImage: "map") }
                .tag(RootTab.map)

            LineeListView(
                atacGtfsStore: atacGtfsStore,
                atacRealtimeService: atacRealtimeService,
                gtfsStore: gtfsStore,
                favoritesStore: favoritesStore,
                vehicleTracker: vehicleTracker,
                transitsRepository: transitsRepository,
                astralTrainRepository: astralTrainRepository
            )
            .tabItem { Label("Linee", systemImage: "list.bullet") }
            .tag(RootTab.linee)

            FavoritesListView(
                favoritesStore: favoritesStore,
                atacGtfsStore: atacGtfsStore,
                atacRealtimeService: atacRealtimeService,
                gtfsStore: gtfsStore,
                vehicleTracker: vehicleTracker,
                transitsRepository: transitsRepository,
                astralTrainRepository: astralTrainRepository
            )
            .tabItem { Label("Preferiti", systemImage: "star.fill") }
            .tag(RootTab.preferiti)

            RemindersListView(
                reminderStore: reminderStore,
                gtfsStore: gtfsStore,
                atacGtfsStore: atacGtfsStore
            )
            .tabItem { Label("Promemoria", systemImage: "bell.fill") }
            .tag(RootTab.reminders)
        }
        .task {
            await gtfsStore.ensureLoaded()
        }
        .task {
            // Independent of Cotral's own GTFS load — Atac/Roma TPL is an
            // additional overlay, not a blocking requirement. If it fails,
            // the app should still work fine for Cotral alone.
            await atacGtfsStore.ensureLoaded()
        }
    }

    private var dataLoadingBannerItems: [DataLoadingBanner.Item] {
        var items: [DataLoadingBanner.Item] = []
        if gtfsStore.state != .ready {
            items.append(.init(id: "cotral", label: "Dati Cotral", state: gtfsStore.state, progress: gtfsStore.downloadProgress) {
                Task { await gtfsStore.retry() }
            })
        }
        if atacGtfsStore.state != .ready {
            items.append(.init(id: "atac", label: "Dati Atac/Roma TPL", state: atacGtfsStore.state, progress: atacGtfsStore.downloadProgress) {
                Task { await atacGtfsStore.retry() }
            })
        }
        return items
    }

    private var mapScreen: some View {
        ZStack(alignment: .top) {
            MapContainerView(
                poles: focusedPoles,
                favoritePoleCodes: favoritesStore.favoritePoleCodes,
                vehicleCoordinate: vehicleTracker.coordinate,
                vehicleIsTreno: vehicleTracker.isTreno,
                vehicleTrackingState: vehicleTracker.state,
                onSelectPole: { pole in selectedPole = pole },
                atacStops: focusedAtacStops,
                atacShapes: focusedShapes,
                onSelectAtacStop: { stop in selectAtacStopGroup(containing: stop) },
                routeLookup: { routeId in
                    if let atacRoute = atacGtfsStore.route(for: routeId) { return atacRoute }
                    // A focused Cotral rail line's shape is drawn via the
                    // same overlay pipeline as Atac's (see `focusedShapes`),
                    // so its color also needs resolving through this same
                    // closure — synthesize an `AtacRoute`-shaped value from
                    // the GTFS rail route so `AtacPolyline` picks `.treno`
                    // (purple) instead of defaulting to `.bus` (blue).
                    guard routeId.hasPrefix("F:"), let railRoute = gtfsStore.route(for: routeId) else { return nil }
                    return AtacRoute(
                        routeId: railRoute.routeId,
                        routeShortName: railRoute.routeShortName,
                        routeLongName: railRoute.routeLongName,
                        kind: .treno,
                        transitOperator: .cotral,
                        colorHex: nil
                    )
                },
                transitVehicles: focusedVehicles,
                onSelectVehicle: { vehicle in
                    selectedVehicle = vehicle
                    focusedRouteId = vehicle.routeId
                },
                userLocation: locationManager.currentLocation,
                pendingCenter: $mapViewModel.pendingCenter,
                onRegionChange: { region in viewportState.regionChanged(region) }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                StopLineSearchBar(
                    viewModel: mapViewModel,
                    onSelectStop: { result in
                        switch result {
                        case .cotral(let stop):
                            selectedPole = mapViewModel.jumpTo(stop: stop)
                        case .atac(let stop):
                            mapViewModel.centerOn(atacStop: stop)
                            selectAtacStopGroup(containing: stop)
                        }
                    },
                    onSelectRoute: { result in
                        switch result {
                        case .cotral(let route):
                            mapViewModel.jumpTo(route: route)
                            focusedRouteId = nil
                            // A rail line's own station list (with tappable
                            // orari) lives in `LineeDetailView`, previously
                            // only reachable from the separate "Linee" tab —
                            // searching a line here just recentered the map
                            // on it with no way to see its schedule, so a
                            // tap would land on whichever pole happened to
                            // be nearest, opening that one station instead
                            // of the line the user actually searched for.
                            searchedCotralRoute = result
                        case .atac(let route):
                            if mapViewModel.jumpTo(atacRoute: route) {
                                focusedRouteId = route.routeId
                            }
                        }
                    }
                )

                if !dataLoadingBannerItems.isEmpty {
                    DataLoadingBanner(items: dataLoadingBannerItems)
                }

                if focusedRouteId != nil {
                    focusedLineBanner
                }

                if case .error(let message) = mapViewModel.state {
                    ErrorBanner(message: message) {
                        reloadAroundUserOrLastPole()
                    }
                }

                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    permissionDeniedBanner
                }

                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    mapControls
                        .padding(.trailing)
                        .padding(.bottom, 16)
                }
            }
        }
        .sheet(item: $selectedPole) { pole in
            PoleDetailSheetContainer(
                pole: pole,
                favoritesStore: favoritesStore,
                vehicleTracker: vehicleTracker,
                transitsRepository: transitsRepository,
                gtfsStore: gtfsStore,
                astralTrainRepository: astralTrainRepository
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAtacStopGroup) { group in
            AtacStopDetailSheet(
                stops: group.stops,
                routeId: isAtacFocus ? focusedRouteId : nil,
                realtimeService: atacRealtimeService,
                atacGtfsStore: atacGtfsStore,
                favoritesStore: favoritesStore
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $searchedCotralRoute) { route in
            NavigationView {
                LineeDetailView(
                    route: route,
                    atacGtfsStore: atacGtfsStore,
                    atacRealtimeService: atacRealtimeService,
                    gtfsStore: gtfsStore,
                    favoritesStore: favoritesStore,
                    vehicleTracker: vehicleTracker,
                    transitsRepository: transitsRepository,
                    astralTrainRepository: astralTrainRepository
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedVehicle) { vehicle in
            Group {
                if vehicle.transitOperator == .cotral {
                    CotralVehicleDetailSheet(vehicle: vehicle, astralTrainRepository: astralTrainRepository)
                        .presentationDetents([.medium, .large])
                } else {
                    AtacVehicleDetailSheet(vehicle: vehicle, realtimeService: atacRealtimeService, atacGtfsStore: atacGtfsStore)
                        .presentationDetents([.medium, .large])
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet()
        }
        .onAppear {
            guard !hasRequestedLocation else { return }
            hasRequestedLocation = true
            locationManager.requestPermission()
            locationManager.startUpdating()

            guard !hasStartedRealtimePolling else { return }
            hasStartedRealtimePolling = true
            atacRealtimeService.startPolling()
            cotralViewportVehicles.startPolling()
        }
        .onChange(of: locationManager.currentLocation) { newLocation in
            guard let newLocation, !hasCenteredOnUserOnce else { return }
            // Only used to get the very first viewport oriented — after
            // that, poles/stops/lines all track wherever the user pans, and
            // recentering again only happens via the explicit "my location"
            // button (`reloadAroundUserOrLastPole`).
            hasCenteredOnUserOnce = true
            mapViewModel.pendingCenter = newLocation
        }
        .onChange(of: viewportState.settledBounds) { bounds in
            guard let bounds else { return }
            mapViewModel.updateViewport(bounds)
            atacViewModel.updateViewport(bounds)
            cotralViewportVehicles.updateVisiblePoles(mapViewModel.poles)
        }
    }

    private var mapControls: some View {
        VStack(spacing: 12) {
            Button {
                reloadAroundUserOrLastPole()
            } label: {
                Image(systemName: "location.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .background(.thinMaterial, in: Circle())

            Button {
                atacViewModel.toggleLinesVisible(bounds: viewportState.settledBounds)
            } label: {
                Image(systemName: atacViewModel.linesVisible ? "point.topleft.down.curvedto.point.bottomright.up.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .background(.thinMaterial, in: Circle())

            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .background(.thinMaterial, in: Circle())
        }
    }

    private var focusedLineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.diagonal")
                .foregroundStyle(Color.accentColor)
            Text("Mostro solo questa linea")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                focusedRouteId = nil
            } label: {
                Label("Reset", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private var permissionDeniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.slash")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Posizione non disponibile")
                    .font(.subheadline.bold())
                Text("Attiva la posizione per vedere le paline vicine, oppure cerca una località.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Impostazioni") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    /// True when the focused line is an Atac/Roma TPL one (vs. a Cotral
    /// `percorso` code, a different id namespace entirely — see
    /// `TransitVehicle.routeId`'s doc comment).
    private var isAtacFocus: Bool {
        guard let routeId = focusedRouteId else { return false }
        return atacGtfsStore.route(for: routeId) != nil
    }

    /// While a line is focused, show only its own shape(s) — across the
    /// whole line, not just the current viewport, since a regional/urban
    /// line easily extends beyond what's on screen. A focused Cotral *bus*
    /// line still has no shape data (never parsed, see `AtacGtfsParsing`'s
    /// doc comment on scale), so that case goes empty rather than showing
    /// unrelated Atac lines — but a focused Cotral *rail* line does, now
    /// that `GTFSStore` parses the (much smaller) rail `shapes.txt`.
    /// Unfocused, falls back to the normal viewport-scoped Atac shapes.
    private var focusedShapes: [AtacLineShape] {
        guard let routeId = focusedRouteId else { return atacViewModel.visibleShapes }
        if isAtacFocus {
            return atacGtfsStore.shapes(forRouteId: routeId)
        }
        // A focused Cotral vehicle's `routeId` is its `percorso`
        // (`CotralTrainRoute`'s raw value for a train, e.g. "RL_PSP-CC") —
        // a different id namespace than GTFS's own rail route ids, so it
        // needs translating via `route_short_name` (not string-built,
        // since nothing guarantees a GTFS route's own id matches its short
        // name even though it happens to for all 3 rail lines today).
        guard let trainRoute = CotralTrainRoute(rawValue: routeId),
              let railRoute = gtfsStore.allRailRoutes().first(where: { $0.routeShortName.uppercased() == trainRoute.gtfsRouteShortName })
        else { return [] }
        return gtfsStore.shapes(forRouteId: railRoute.routeId)
    }

    /// While a line is focused, show only stops actually served by it
    /// (exact GTFS route<->stop membership) — otherwise unrelated stops
    /// from every other line clutter the isolated view for no reason.
    /// Grouped by name to one pin per physical station (same idea as the
    /// "Linee" browser's own station list) — a real station is often split
    /// across several GTFS `stop_id`s, one per platform/direction, which
    /// otherwise shows up as several near-identical pins on top of each
    /// other (e.g. two "Colosseo" dots). Tapping one still resolves every
    /// platform via `AtacGtfsStore.stopsSharingName(with:)`, not just this
    /// representative one.
    private var focusedAtacStops: [AtacStop] {
        let stops: [AtacStop]
        if let routeId = focusedRouteId {
            guard isAtacFocus else { return [] }
            stops = atacGtfsStore.stopsForRoute(routeId)
        } else {
            stops = atacViewModel.visibleStops
        }
        return groupedStopsByName(stops).map(\.anchor)
    }

    /// While a line is focused, show only vehicles on that same line.
    private var focusedVehicles: [TransitVehicle] {
        let all = atacRealtimeService.vehicles + cotralViewportVehicles.vehicles
        guard let routeId = focusedRouteId else { return all }
        return all.filter { $0.routeId == routeId }
    }

    /// While a line is focused, hide Cotral poles entirely rather than
    /// showing an inaccurate subset: a focused Atac line has nothing to do
    /// with any Cotral pole, and a focused Cotral line's own `percorso`
    /// code isn't a GTFS route id, so there's no reliable way to show "only
    /// this Cotral line's poles" — hiding all of them still delivers the
    /// clean, decluttered view that was actually asked for.
    private var focusedPoles: [Pole] {
        focusedRouteId == nil ? mapViewModel.poles : []
    }

    private func reloadAroundUserOrLastPole() {
        if let location = locationManager.currentLocation {
            mapViewModel.pendingCenter = location
        }
    }

    /// A map pin or search result only ever carries the one `AtacStop` it
    /// was built from (see `focusedAtacStops`'s doc comment for why that's
    /// just a representative platform) — this resolves it back to every
    /// platform sharing its name before opening the sheet, so the direction
    /// picker is available from any entry point.
    private func selectAtacStopGroup(containing stop: AtacStop) {
        let stops = atacGtfsStore.stopsSharingName(with: stop)
        selectedAtacStopGroup = AtacStopGroup(name: stop.stopName.trimmingCharacters(in: .whitespaces), stops: stops)
    }
}

/// Owns a `PoleDetailViewModel` scoped to wherever this is presented from
/// (transits polling only — vehicle tracking lives in the shared
/// `VehicleTracker` passed in from the root, so it survives the sheet being
/// dismissed). Reused both by the map's own pole sheet and by the "Linee"
/// browser's stop lists (internal, not private, for that second use), so
/// tapping a stop there opens the exact same schedule view.
struct PoleDetailSheetContainer: View {
    @StateObject private var viewModel: PoleDetailViewModel
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker

    init(
        pole: Pole,
        favoritesStore: FavoritesStore,
        vehicleTracker: VehicleTracker,
        transitsRepository: TransitsRepository,
        gtfsStore: GTFSStore,
        astralTrainRepository: AstralTrainRepository
    ) {
        _viewModel = StateObject(wrappedValue: PoleDetailViewModel(
            pole: pole,
            vehicleTracker: vehicleTracker,
            transitsRepository: transitsRepository,
            gtfsStore: gtfsStore,
            astralTrainRepository: astralTrainRepository
        ))
        self.favoritesStore = favoritesStore
        self.vehicleTracker = vehicleTracker
    }

    var body: some View {
        PoleDetailSheetBody(viewModel: viewModel, favoritesStore: favoritesStore, vehicleTracker: vehicleTracker)
    }
}
