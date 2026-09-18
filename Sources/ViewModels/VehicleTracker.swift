import CoreLocation
import Foundation

/// Tracks at most one live vehicle at a time, independent of which pole's
/// detail sheet is currently open. Owned once at the app root so the map
/// marker keeps animating (and the loss banner keeps working) even if the
/// sheet that started tracking gets dismissed.
@MainActor
final class VehicleTracker: ObservableObject {
    @Published private(set) var vehicleCode: String?
    /// Whether the currently-followed vehicle is a train rather than a bus —
    /// set once at the call site that starts following, which already knows
    /// this from the pole/transit it came from (`Pole.isTreno`). Exists so
    /// the tracking banner and map pin can say "treno"/"bus" correctly
    /// instead of hardcoding "bus" for everything this tracker follows.
    @Published private(set) var isTreno: Bool = false
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var state: VehicleTrackingState = .idle
    @Published private(set) var lastUpdated: Date?

    private let repository: VehicleRepository
    private var pollTask: Task<Void, Never>?
    private var consecutiveMisses = 0

    init(repository: VehicleRepository) {
        self.repository = repository
    }

    func isFollowing(_ code: String) -> Bool {
        vehicleCode == code
    }

    func toggleFollowing(_ code: String, isTreno: Bool = false) {
        if isFollowing(code) {
            stopFollowing()
        } else {
            startFollowing(code, isTreno: isTreno)
        }
    }

    func startFollowing(_ code: String, isTreno: Bool = false) {
        pollTask?.cancel()
        vehicleCode = code
        self.isTreno = isTreno
        coordinate = nil
        state = .tracking
        consecutiveMisses = 0
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh(code)
                try? await Task.sleep(nanoseconds: UInt64(Config.vehiclePositionPollInterval * 1_000_000_000))
            }
        }
    }

    func stopFollowing() {
        pollTask?.cancel()
        pollTask = nil
        vehicleCode = nil
        isTreno = false
        coordinate = nil
        state = .idle
        consecutiveMisses = 0
    }

    /// Called by a pole's transits poll when it observes `automezzo.isAlive == false`
    /// for the vehicle we're currently following — a more immediate signal than
    /// waiting out the position-poll miss threshold.
    func reportOffline(for code: String) {
        guard vehicleCode == code, state != .idle else { return }
        markLost()
    }

    private func refresh(_ code: String) async {
        do {
            let positions = try await repository.positions(vehicleCode: code)
            if let newCoordinate = positions.first?.latestCoordinate {
                coordinate = newCoordinate
                state = .tracking
                lastUpdated = Date()
                consecutiveMisses = 0
            } else {
                registerMiss()
            }
        } catch {
            registerMiss()
        }
    }

    private func registerMiss() {
        consecutiveMisses += 1
        if consecutiveMisses >= Config.vehicleTrackingLossThreshold {
            markLost()
        }
    }

    private func markLost() {
        guard state != .idle else { return }
        state = .lost(lastUpdate: lastUpdated)
    }
}
