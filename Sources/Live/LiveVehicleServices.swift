import CoreLocation
import Foundation

/// The whole Atac / Roma TPL fleet, refreshed every `Config.atacFleetPollInterval`.
@MainActor
final class AtacFleetService: ObservableObject {
    @Published private(set) var vehicles: [TransitVehicle] = []
    @Published private(set) var lastUpdated: Date?
    /// Last refresh failed (vehicles keep their last known positions).
    @Published private(set) var error: APIError?
    @Published private(set) var hasLoadedOnce = false

    private let api: MadovaiAPI
    private lazy var poller = Poller(interval: Config.atacFleetPollInterval) { [weak self] in
        await self?.refresh()
    }
    var onResult: ((Result<Void, Error>) -> Void)?

    init(api: MadovaiAPI = .shared) {
        self.api = api
    }

    func start() { poller.start() }
    func refreshNow() { poller.refreshNow() }

    func refresh() async {
        do {
            let result = try await api.atacVehicles()
            vehicles = result.vehicles
            lastUpdated = result.updated ?? Date()
            error = nil
            hasLoadedOnce = true
            onResult?(.success(()))
        } catch {
            guard !error.isCancellation else { return }
            self.error = error as? APIError ?? .offline
            onResult?(.failure(error))
        }
    }

    func vehicle(id: String) -> TransitVehicle? {
        vehicles.first { $0.id == id }
    }
}

/// Cotral vehicles near the visible poles. There's no "every Cotral vehicle"
/// feed: a vehicle only shows up through the transits of a pole it serves,
/// so this asks the backend about whichever poles are on screen.
@MainActor
final class CotralViewportVehicleService: ObservableObject {
    @Published private(set) var vehicles: [TransitVehicle] = []

    private let api: MadovaiAPI
    private var poleCodes: [String] = []
    private var byId: [String: TransitVehicle] = [:]
    private var misses: [String: Int] = [:]
    private var isScanning = false
    private var needsRescan = false
    private lazy var poller = Poller(interval: Config.cotralViewportVehiclePollInterval) { [weak self] in
        await self?.requestScan()
    }

    init(api: MadovaiAPI = .shared) {
        self.api = api
    }

    func start() { poller.start() }
    func refreshNow() { poller.refreshNow() }

    /// Called whenever the visible Cotral poles change (viewport settle).
    func updateVisiblePoles(_ poles: [Pole]) {
        let codes = Array(poles.compactMap(\.codicePalina).prefix(Config.cotralViewportPoleQueryLimit))
        guard codes != poleCodes else { return }
        poleCodes = codes
        Task { await requestScan() }
    }

    /// Serialises every trigger (timer + viewport) through one gate: a
    /// request arriving mid-scan becomes exactly one follow-up scan, so two
    /// scans can never finish out of order and overwrite each other.
    func requestScan() async {
        if isScanning {
            needsRescan = true
            return
        }
        isScanning = true
        defer { isScanning = false }
        await scan()
        while needsRescan {
            needsRescan = false
            await scan()
        }
    }

    private func scan() async {
        let codes = poleCodes
        guard !codes.isEmpty else {
            byId = [:]
            misses = [:]
            if !vehicles.isEmpty { vehicles = [] }
            return
        }
        guard let fresh = try? await api.cotralVehicles(poles: codes) else { return }
        // A stale result for poles that are no longer visible is still
        // merged: those vehicles simply age out through the miss counter.
        let merged = Self.merge(previous: byId, previousMisses: misses, fresh: fresh, lossThreshold: Config.vehicleTrackingLossThreshold)
        byId = merged.byId
        misses = merged.misses
        vehicles = merged.byId.values.sorted { $0.id < $1.id }
    }

    /// A vehicle missing from one scan (any hiccup in the two upstream round
    /// trips behind it) keeps its last position for up to `lossThreshold`
    /// scans instead of blinking off the map and back. Pure, for tests.
    nonisolated static func merge(
        previous: [String: TransitVehicle], previousMisses: [String: Int], fresh: [TransitVehicle], lossThreshold: Int
    ) -> (byId: [String: TransitVehicle], misses: [String: Int]) {
        var byId: [String: TransitVehicle] = [:]
        var misses: [String: Int] = [:]
        for vehicle in fresh {
            byId[vehicle.id] = vehicle
            misses[vehicle.id] = 0
        }
        for (id, vehicle) in previous where byId[id] == nil {
            let count = (previousMisses[id] ?? 0) + 1
            guard count <= lossThreshold else { continue }
            byId[id] = vehicle
            misses[id] = count
        }
        return (byId, misses)
    }
}

enum VehicleTrackingState: Equatable {
    case idle
    case tracking
    case lost(lastUpdate: Date?)
}

/// The single Cotral vehicle the user chose to follow ("Segui"), owned at the
/// app root so the marker keeps moving after its sheet is closed.
@MainActor
final class VehicleTracker: ObservableObject {
    @Published private(set) var vehicleCode: String?
    @Published private(set) var isTreno = false
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var state: VehicleTrackingState = .idle
    @Published private(set) var lastUpdated: Date?

    private let api: MadovaiAPI
    private var poller: Poller?
    private var consecutiveMisses = 0

    init(api: MadovaiAPI = .shared) {
        self.api = api
    }

    func isFollowing(_ code: String?) -> Bool {
        guard let code else { return false }
        return vehicleCode == code
    }

    func toggleFollowing(_ code: String, isTreno: Bool = false) {
        isFollowing(code) ? stopFollowing() : startFollowing(code, isTreno: isTreno)
    }

    func startFollowing(_ code: String, isTreno: Bool = false) {
        poller?.stop()
        vehicleCode = code
        self.isTreno = isTreno
        coordinate = nil
        lastUpdated = nil
        state = .tracking
        consecutiveMisses = 0
        let poller = Poller(interval: Config.vehiclePositionPollInterval) { [weak self] in
            await self?.refresh(code)
        }
        self.poller = poller
        poller.start()
    }

    func stopFollowing() {
        poller?.stop()
        poller = nil
        vehicleCode = nil
        isTreno = false
        coordinate = nil
        lastUpdated = nil
        state = .idle
        consecutiveMisses = 0
    }

    /// A pole's transit poll saw `vehicleAlive == false` for the followed
    /// vehicle — more immediate than waiting out the miss threshold.
    func reportOffline(for code: String) {
        guard vehicleCode == code, state != .idle else { return }
        markLost()
    }

    private func refresh(_ code: String) async {
        do {
            let position = try await api.cotralVehicle(code: code)
            guard vehicleCode == code else { return }
            if let position {
                coordinate = position
                state = .tracking
                lastUpdated = Date()
                consecutiveMisses = 0
            } else {
                registerMiss()
            }
        } catch {
            guard !error.isCancellation, vehicleCode == code else { return }
            registerMiss()
        }
    }

    private func registerMiss() {
        consecutiveMisses += 1
        if consecutiveMisses >= Config.vehicleTrackingLossThreshold { markLost() }
    }

    private func markLost() {
        guard state != .idle else { return }
        state = .lost(lastUpdate: lastUpdated)
    }
}
