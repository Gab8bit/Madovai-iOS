import Foundation

/// Scheduled departures-per-station for Cotral's 3 rail lines (Metromare,
/// Roma-Viterbo Urbana, Roma-Viterbo Extraurbana), from the separate
/// train-schedule widget endpoint — not PIV.do/Automezzi.do, not GTFS. See
/// `CotralTrainScheduleClient`.
@MainActor
final class CotralTrainScheduleRepository {
    private let client: CotralTrainScheduleClient

    init(client: CotralTrainScheduleClient = .shared) {
        self.client = client
    }

    func schedule(for route: CotralTrainRoute, date: Date = Date()) async throws -> [CotralTrainStationSchedule] {
        try await client.fetchSchedule(for: route, date: date)
    }
}
