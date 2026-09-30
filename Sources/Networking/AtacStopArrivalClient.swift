import Foundation
import SwiftProtobuf

/// The next upcoming arrivals at one Atac/Roma TPL stop, decoded straight
/// from GTFS-Realtime `trip_updates` — the exact same feed/proto types
/// `AtacRealtimeService` already uses, just without its `AtacGtfsStore`
/// dependency (needed there only to enrich results with route labels and
/// headsigns, neither of which a Promemoria notification needs: the stop
/// name and line are already known from when the reminder was created).
/// Standing up a full `AtacGtfsStore` — a 47MB feed — just to answer "what's
/// next at this one stop" would be both unnecessary and too slow for a
/// background task's short execution window.
actor AtacStopArrivalClient {
    static let shared = AtacStopArrivalClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Config.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    /// The next `limit` arrivals at `stopId`, soonest first — more than one
    /// so a caller can report a "prossimo utile" fallback time when the
    /// very next one turns out to be cancelled (see
    /// `ReminderDepartureStatus`'s doc comment).
    func upcomingArrivals(stopId: String, limit: Int = 2) async throws -> [AtacStopArrival] {
        let (data, response) = try await session.data(from: Config.atacTripUpdatesURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode)
        }
        let feed = try TransitRealtime_FeedMessage(serializedBytes: data)

        var arrivals: [AtacStopArrival] = []
        for entity in feed.entity {
            guard entity.hasTripUpdate else { continue }
            let tripUpdate = entity.tripUpdate
            // Either signal means "soppressa" for a rider at this specific
            // stop — the whole run being cancelled/deleted, or just this
            // stop being skipped within an otherwise-running trip (see
            // `proto/gtfs-realtime.proto`'s two separate
            // `ScheduleRelationship` enums, one per trip and one per stop).
            let tripCancelled = tripUpdate.hasTrip
                && tripUpdate.trip.hasScheduleRelationship
                && (tripUpdate.trip.scheduleRelationship == .canceled || tripUpdate.trip.scheduleRelationship == .deleted)

            for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                guard stopTimeUpdate.hasStopID, stopTimeUpdate.stopID == stopId else { continue }

                let event: TransitRealtime_TripUpdate.StopTimeEvent?
                if stopTimeUpdate.hasArrival {
                    event = stopTimeUpdate.arrival
                } else if stopTimeUpdate.hasDeparture {
                    event = stopTimeUpdate.departure
                } else {
                    event = nil
                }
                guard let event, event.hasTime, event.time > 0 else { continue }

                let time = Date(timeIntervalSince1970: TimeInterval(event.time))
                guard time.timeIntervalSinceNow > -120 else { continue }

                let stopSkipped = stopTimeUpdate.hasScheduleRelationship && stopTimeUpdate.scheduleRelationship == .skipped
                arrivals.append(AtacStopArrival(
                    time: time,
                    delaySeconds: event.hasDelay ? Int(event.delay) : nil,
                    isCancelled: tripCancelled || stopSkipped
                ))
            }
        }
        return Array(arrivals.sorted { $0.time < $1.time }.prefix(limit))
    }
}

struct AtacStopArrival {
    let time: Date
    let delaySeconds: Int?
    let isCancelled: Bool
}
