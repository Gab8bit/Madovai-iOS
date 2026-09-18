import Foundation

/// Opportunistically shows Cotral vehicles for whatever poles are
/// currently visible on screen. There is no "give me every active Cotral
/// vehicle" endpoint — a vehicle only becomes visible after querying
/// `/transits` for a specific pole and finding a monitored run with a
/// vehicle code, so this is fundamentally partial coverage, never the full
/// regional fleet (see `TransitVehicle.VisibilityScope.visibleAreaOnly`).
@MainActor
final class CotralViewportVehicleService: ObservableObject {
    @Published private(set) var vehicles: [TransitVehicle] = []

    private let transitsRepository: TransitsRepository
    private let vehicleRepository: VehicleRepository
    private var currentPoleCodes: [String] = []
    private var pollTask: Task<Void, Never>?

    /// Last-known entry per vehicle id, kept across scans that fail to
    /// reproduce it — see `scan()`'s merge step for why.
    private var vehiclesById: [String: TransitVehicle] = [:]
    private var missesById: [String: Int] = [:]
    private var isScanning = false
    private var needsRescan = false

    init(transitsRepository: TransitsRepository, vehicleRepository: VehicleRepository) {
        self.transitsRepository = transitsRepository
        self.vehicleRepository = vehicleRepository
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Config.cotralViewportVehiclePollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.requestScan()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Called whenever the visible Cotral poles change (viewport settle).
    /// Triggers an immediate scan of the new set.
    func updateVisiblePoles(_ poles: [Pole]) {
        currentPoleCodes = Array(poles.compactMap(\.codicePalina).prefix(Config.cotralViewportPoleQueryLimit))
        Task { await requestScan() }
    }

    /// `scan()` does two chained round trips (transits, then positions) and
    /// isn't cheap to run twice at once — a periodic tick and a
    /// viewport-settle can otherwise both call it concurrently and finish
    /// out of order, with whichever happens to complete *last* winning even
    /// if it was the one that started *first* and saw a transient failure.
    /// That race (not simply the ~18s poll cadence) was the real cause of
    /// vehicles appearing for a couple seconds then vanishing. Serializing
    /// every trigger through here — coalescing a request that arrives
    /// mid-scan into exactly one follow-up scan rather than dropping it or
    /// letting it run concurrently — fixes that without losing
    /// responsiveness to viewport changes.
    private func requestScan() async {
        guard !isScanning else {
            needsRescan = true
            return
        }
        await scan()
        while needsRescan {
            needsRescan = false
            await scan()
        }
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }

        let poleCodes = currentPoleCodes
        guard !poleCodes.isEmpty else {
            // The viewport genuinely has no Cotral poles in it any more —
            // unlike a fetch failure below, there's nothing to keep a grace
            // period for.
            vehiclesById = [:]
            missesById = [:]
            vehicles = []
            return
        }

        // Keep the originating Transit (line code, run id) per vehicle, not
        // just its code — needed for the "focus this line" / trip-detail
        // interaction when a vehicle is tapped on the map.
        let transitsByVehicle = await withTaskGroup(of: [(String, Transit)].self) { group -> [String: Transit] in
            for poleCode in poleCodes {
                group.addTask { [transitsRepository] in
                    guard let result = try? await transitsRepository.transits(poleCode: poleCode) else { return [] }
                    return result.transits
                        .filter(\.canTrackVehicle)
                        .compactMap { transit in transit.automezzo.codice.map { ($0, transit) } }
                }
            }
            var merged: [String: Transit] = [:]
            for await found in group {
                for (code, transit) in found { merged[code] = transit }
            }
            return merged
        }

        let freshVehicles = await withTaskGroup(of: TransitVehicle?.self) { group -> [TransitVehicle] in
            for (code, transit) in transitsByVehicle {
                group.addTask { [vehicleRepository] in
                    guard let positions = try? await vehicleRepository.positions(vehicleCode: code),
                          let coordinate = positions.first?.latestCoordinate
                    else { return nil }
                    let routeId = transit.percorso.isEmpty ? nil : transit.percorso
                    return TransitVehicle(
                        id: "cotral-\(code)",
                        coordinate: coordinate,
                        bearing: nil,
                        routeId: routeId,
                        routeLabel: routeId,
                        kind: .bus,
                        transitOperator: .cotral,
                        scope: .visibleAreaOnly,
                        delaySeconds: transit.isDelayReliable ? transit.ritardoSeconds : nil,
                        tripId: transit.idCorsa.isEmpty ? nil : transit.idCorsa
                    )
                }
            }
            var results: [TransitVehicle] = []
            for await vehicle in group {
                if let vehicle { results.append(vehicle) }
            }
            return results
        }

        // A vehicle missing from this cycle's result (an empty per-pole
        // transits response, a `canTrackVehicle`/`isAlive` flip for one
        // poll, a slow/failed position lookup — any transient hiccup
        // anywhere in the two round trips above) keeps showing at its last
        // known position for a couple of misses, exactly like
        // `VehicleTracker` already does for the single followed vehicle,
        // instead of blinking off the map and back.
        var mergedById: [String: TransitVehicle] = [:]
        var mergedMisses: [String: Int] = [:]
        for vehicle in freshVehicles {
            mergedById[vehicle.id] = vehicle
            mergedMisses[vehicle.id] = 0
        }
        let freshIds = Set(freshVehicles.map(\.id))
        for (id, vehicle) in vehiclesById where !freshIds.contains(id) {
            let misses = (missesById[id] ?? 0) + 1
            guard misses <= Config.vehicleTrackingLossThreshold else { continue }
            mergedById[id] = vehicle
            mergedMisses[id] = misses
        }

        vehiclesById = mergedById
        missesById = mergedMisses
        vehicles = Array(mergedById.values)
    }
}
