import Foundation

/// The app's long-lived services, created once and shared by every tab, so
/// the fleet poll, the followed vehicle and the favorites survive tab
/// switches and sheet dismissals.
@MainActor
final class AppEnvironment {
    let api: MadovaiAPI
    let connectivity: ConnectivityMonitor
    let linesStore: LinesStore
    let favoritesStore: FavoritesStore
    let reminderStore: ReminderStore
    let vehicleTracker: VehicleTracker
    let atacFleet: AtacFleetService
    let cotralVehicles: CotralViewportVehicleService
    let mapViewModel: MapViewModel
    let locationManager: LocationManager

    private var started = false

    init(api: MadovaiAPI = .shared) {
        self.api = api
        connectivity = ConnectivityMonitor(api: api)
        linesStore = LinesStore(api: api)
        favoritesStore = FavoritesStore()
        reminderStore = ReminderStore.shared
        vehicleTracker = VehicleTracker(api: api)
        atacFleet = AtacFleetService(api: api)
        cotralVehicles = CotralViewportVehicleService(api: api)
        mapViewModel = MapViewModel(api: api, linesStore: linesStore, connectivity: connectivity)
        locationManager = LocationManager()
    }

    /// Starts polling and monitoring (idempotent).
    func start() {
        guard !started else { return }
        started = true
        connectivity.start()
        atacFleet.onResult = { [weak self] result in
            switch result {
            case .success: self?.connectivity.reportSuccess()
            case .failure(let error): self?.connectivity.report(error)
            }
        }
        atacFleet.start()
        cotralVehicles.start()
        connectivity.onReconnect { [weak self] in
            guard let self else { return }
            atacFleet.refreshNow()
            cotralVehicles.refreshNow()
            mapViewModel.reload()
            if linesStore.lines == nil { linesStore.retry() }
        }
        Task { await reminderStore.resolveMissingTrainStationIds(api: api) }
    }
}
