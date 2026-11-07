import Foundation

/// "What is the next departure for this reminder", using the backend. Kept
/// separate from `ReminderScheduler` (which deals with `BGTaskScheduler`,
/// not unit-testable) so the fetch logic can be tested with a stubbed API.
///
/// Returns nil when there's nothing upcoming; throws on network/server
/// failure — the scheduler retries both cases without notifying.
struct ReminderStatusFetcher {
    let api: MadovaiAPI

    init(api: MadovaiAPI = .shared) {
        self.api = api
    }

    func status(for reminder: Reminder, now: Date = Date()) async throws -> ReminderDepartureStatus? {
        switch reminder.source {
        case .cotralBus(let poleCode):
            let response = try await api.cotralTransits(pole: poleCode)
            return ReminderDepartureStatus.nextUpcoming(from: response.transits, now: now)

        case .cotralTrain(let stationName, let route, let stopId):
            if let stopId {
                let response = try await api.rail(stopId: stopId)
                guard let direction = Self.direction(for: route, in: response.directions) else { return nil }
                return ReminderDepartureStatus.nextUpcoming(from: direction.entries.upcoming(from: now))
            }
            // Pre-2.0 reminder whose station id hasn't been resolved yet:
            // the line-wide ASTRAL view only knows each station's next
            // train, so a cancellation can't name the following one here.
            let line = try await api.astralLine(route: route.rawValue)
            guard let station = line.stations.first(where: { Self.sameName($0.name, stationName) }),
                  let next = station.next
            else { return nil }
            return ReminderDepartureStatus.nextUpcoming(from: [next].upcoming(from: now))

        case .atacStop(let stopId):
            let arrivals = try await api.atacLive(stopIds: [stopId])[stopId] ?? []
            return ReminderDepartureStatus.nextUpcoming(from: arrivals, now: now)
        }
    }

    /// The `rail` direction matching the reminder's route: by route code
    /// when the backend provides it, else by destination name.
    static func direction(for route: CotralTrainRoute, in directions: [AstralScheduleDirection]) -> AstralScheduleDirection? {
        directions.first { $0.route == route.rawValue }
            ?? directions.first { sameName($0.destination, route.destinationName) }
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).compare(b.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
