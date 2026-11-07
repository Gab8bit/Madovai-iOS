import CoreLocation
import MapKit
import SwiftUI

/// The app's 4 top-level sections in a standard bottom `TabView` (the
/// system tab bar picks up the platform's Liquid Glass material for free).
struct ContentView: View {
    let env: AppEnvironment

    var body: some View {
        TabView {
            MapScreen(
                env: env,
                model: env.mapViewModel,
                fleet: env.atacFleet,
                cotralVehicles: env.cotralVehicles,
                tracker: env.vehicleTracker,
                favoritesStore: env.favoritesStore,
                locationManager: env.locationManager,
                connectivity: env.connectivity
            )
            .tabItem { Label("Mappa", systemImage: "map") }

            LineeListView(linesStore: env.linesStore, env: env)
                .tabItem { Label("Linee", systemImage: "list.bullet") }

            FavoritesListView(favoritesStore: env.favoritesStore, env: env)
                .tabItem { Label("Preferiti", systemImage: "star.fill") }

            RemindersListView(reminderStore: env.reminderStore)
                .tabItem { Label("Promemoria", systemImage: "bell.fill") }
        }
        .onAppear { env.start() }
    }
}

/// Which sheet the map is showing. One `.sheet(item:)` for all of them, so
/// opening one while another is closing can't race.
enum MapSheet: Identifiable {
    case pole(Pole)
    case atacStop(AtacStopGroup)
    case vehicle(TransitVehicle)
    case line(RouteInfo)
    case info

    var id: String {
        switch self {
        case .pole(let pole): return "pole:\(pole.id)"
        case .atacStop(let group): return "atac:\(group.id)"
        case .vehicle(let vehicle): return "vehicle:\(vehicle.id)"
        case .line(let route): return "line:\(route.id)"
        case .info: return "info"
        }
    }
}

struct MapScreen: View {
    let env: AppEnvironment
    @ObservedObject var model: MapViewModel
    @ObservedObject var fleet: AtacFleetService
    @ObservedObject var cotralVehicles: CotralViewportVehicleService
    @ObservedObject var tracker: VehicleTracker
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var connectivity: ConnectivityMonitor

    @StateObject private var search = SearchModel()
    @State private var sheet: MapSheet?
    @State private var hasCenteredOnUser = false
    @State private var hasRequestedLocation = false

    private var vehicleStyle: VehicleMarkerStyle {
        (model.viewport?.zoom ?? 15) >= Config.vehicleBadgeZoom ? .badge : .dot
    }

    private var shownVehicles: [TransitVehicle] {
        MapViewModel.visibleVehicles(fleet.vehicles + cotralVehicles.vehicles, focusRouteId: model.focus?.routeId, viewport: model.viewport)
    }

    private var followedMarker: FollowedVehicleMarker? {
        guard let coordinate = tracker.coordinate else { return nil }
        let isLost: Bool = { if case .lost = tracker.state { return true } else { return false } }()
        return FollowedVehicleMarker(coordinate: coordinate, isTreno: tracker.isTreno, isLost: isLost)
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(
                poles: model.shownPoles,
                favoritePoleCodes: favoritesStore.favoritePoleCodes,
                atacStops: model.shownAtacStops,
                shapes: model.shownShapes,
                vehicles: shownVehicles,
                vehicleStyle: vehicleStyle,
                followed: followedMarker,
                cameraRequest: model.cameraRequest,
                onSelectPole: { sheet = .pole($0) },
                onSelectAtacStop: { stop in
                    let focusRoute = model.focus?.kind == .atac ? model.focus?.routeId : nil
                    sheet = .atacStop(AtacStopGroup(name: stop.stopName, stops: [stop], routeId: focusRoute))
                },
                onSelectVehicle: { vehicle in
                    sheet = .vehicle(vehicle)
                    model.focus(routeId: vehicle.routeId)
                },
                onViewportChange: { model.viewportSettled($0) }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                StopLineSearchBar(model: search, onSelectStop: selectStop, onSelectRoute: selectRoute)
                banners
                Spacer()
                bottomHints
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    mapControls
                        .padding(.trailing)
                        .padding(.bottom, 24)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isLoading)
        .animation(.easeInOut(duration: 0.2), value: model.focus)
        .animation(.easeInOut(duration: 0.2), value: connectivity.isOnline)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .onAppear {
            guard !hasRequestedLocation else { return }
            hasRequestedLocation = true
            locationManager.requestPermission()
            locationManager.startUpdating()
        }
        .onChange(of: locationManager.currentLocation) { location in
            // Only orients the very first viewport; afterwards the map is
            // the user's (re-centring only via the location button).
            guard let location, !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            model.center(on: location, meters: 1200)
        }
        .onChange(of: model.poles) { poles in
            cotralVehicles.updateVisiblePoles(poles)
        }
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if !connectivity.isOnline {
            ErrorBanner(
                title: "Sei offline",
                message: "Controlla la connessione: posizioni e orari non si aggiornano finché non torni online.",
                systemImage: "wifi.slash"
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if connectivity.serverState == .preparing {
            ErrorBanner(
                title: "Dati non ancora disponibili",
                message: "Il server sta preparando i dati delle linee. Riprova tra qualche minuto.",
                systemImage: "hourglass",
                tint: .orange,
                retry: { connectivity.checkServer(); model.reload() }
            )
        } else if case .unreachable(let message) = connectivity.serverState {
            ErrorBanner(title: "Server non raggiungibile", message: message, retry: retryAll)
        } else if let error = model.dataError {
            ErrorBanner(message: error.message, retry: retryAll)
        } else if let error = fleet.error, fleet.vehicles.isEmpty || !fleet.hasLoadedOnce {
            ErrorBanner(title: "Veicoli non disponibili", message: error.message, systemImage: "bus", tint: .orange, retry: retryAll)
        }

        if model.isLoading && model.dataError == nil && connectivity.isOnline {
            LoadingPill()
                .transition(.opacity)
        }

        if let focus = model.focus {
            focusBanner(focus)
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let notice = model.notice {
            ErrorBanner(title: "Nessun risultato", message: notice, systemImage: "magnifyingglass", tint: .secondary, dismiss: { model.notice = nil })
        }

        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            permissionDeniedBanner
        }
    }

    @ViewBuilder
    private var bottomHints: some View {
        if model.focus == nil, model.isZoomedOutForData {
            HintPill(text: (model.viewport?.zoom ?? 0) < Config.minVehicleZoom
                     ? "Avvicina la mappa per vedere mezzi e fermate"
                     : "Avvicina la mappa per vedere le fermate")
                .padding(.bottom, 24)
                .transition(.opacity)
        }
    }

    private func focusBanner(_ focus: LineFocus) -> some View {
        BannerCard {
            HStack(spacing: 10) {
                if focus.kind == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mostro solo questa linea").font(.subheadline.weight(.semibold))
                    if let name = focusTitle(focus) {
                        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    model.clearFocus()
                } label: {
                    Label("Reset", systemImage: "xmark.circle.fill").font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func focusTitle(_ focus: LineFocus) -> String? {
        if let train = CotralTrainRoute(rawValue: focus.routeId) { return "\(train.lineName) · \(train.directionLabel)" }
        if let route = focus.route { return route.isMetro || route.rail ? route.title : "Linea \(route.title)" }
        return focus.kind == .loading ? nil : "Linea \(focus.routeId)"
    }

    private var permissionDeniedBanner: some View {
        BannerCard {
            HStack(spacing: 12) {
                Image(systemName: "location.slash").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Posizione non disponibile").font(.subheadline.bold())
                    Text("Attiva la posizione per vedere le paline vicine, oppure cerca una località.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Impostazioni") { openSettings() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: Controls

    private var mapControls: some View {
        VStack(spacing: 12) {
            controlButton(systemImage: "location.fill", label: "La mia posizione") { goToMyLocation() }
            controlButton(
                systemImage: model.linesVisible ? "point.topleft.down.curvedto.point.bottomright.up.fill" : "point.topleft.down.curvedto.point.bottomright.up",
                label: model.linesVisible ? "Nascondi le linee" : "Mostra le linee",
                isOn: model.linesVisible
            ) { model.toggleLines() }
            controlButton(systemImage: "info.circle", label: "Informazioni") { sheet = .info }
        }
    }

    private func controlButton(systemImage: String, label: String, isOn: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 46, height: 46)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func selectStop(_ stop: SearchStop) {
        model.center(on: stop.coordinate)
        if stop.isCotral {
            sheet = .pole(stop.asPole)
        } else {
            sheet = .atacStop(AtacStopGroup(name: stop.name, stops: [stop.asAtacStop]))
        }
    }

    private func selectRoute(_ route: RouteInfo) {
        Task {
            if route.isCotral {
                if await model.showCotralRoute(route) { sheet = .line(route) }
            } else {
                await model.showAtacRoute(route)
            }
        }
    }

    private func goToMyLocation() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            openSettings()
        case .notDetermined:
            locationManager.requestPermission()
        default:
            if let location = locationManager.currentLocation {
                model.center(on: location)
            } else {
                locationManager.startUpdating()
            }
        }
    }

    private func retryAll() {
        connectivity.checkServer()
        model.reload()
        fleet.refreshNow()
        cotralVehicles.refreshNow()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: MapSheet) -> some View {
        switch sheet {
        case .pole(let pole):
            PoleSheet(pole: pole, favoritesStore: favoritesStore, tracker: tracker)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .atacStop(let group):
            AtacStopSheet(group: group, favoritesStore: favoritesStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .vehicle(let vehicle):
            Group {
                if vehicle.isCotral {
                    CotralVehicleSheet(vehicle: vehicle)
                } else {
                    AtacVehicleSheet(vehicle: vehicle, fleet: fleet)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .line(let route):
            LineSheet(route: route, env: env)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .info:
            InfoSheet()
        }
    }
}
