import CoreLocation
import Foundation
import SwiftProtobuf

/// Polls Rome's two GTFS-Realtime (protobuf) feeds and decodes them with
/// SwiftProtobuf. Unlike Cotral, a single `vehicle_positions` call returns
/// every active vehicle in the network at once — see `TransitVehicle.VisibilityScope`.
@MainActor
final class AtacRealtimeService: ObservableObject {
    @Published private(set) var vehicles: [TransitVehicle] = []
    /// stopId -> upcoming predictions, sorted soonest first. Built entirely
    /// from `trip_updates` — see `AtacGtfsParsing`'s doc comment for why.
    @Published private(set) var stopPredictions: [String: [AtacStopPrediction]] = [:]
    /// tripId -> full stop-by-stop itinerary, sorted by stop sequence —
    /// "tutti gli orari della corsa corrente" for a tapped vehicle.
    @Published private(set) var tripStopTimes: [String: [AtacTripStopTime]] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

    private let gtfsStore: AtacGtfsStore
    private let session: URLSession
    private var pollTask: Task<Void, Never>?

    init(gtfsStore: AtacGtfsStore) {
        self.gtfsStore = gtfsStore
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Config.requestTimeout
        session = URLSession(configuration: configuration)
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: UInt64(Config.atacRealtimePollInterval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() async {
        do {
            async let vehiclesData = fetch(Config.atacVehiclePositionsURL)
            async let updatesData = fetch(Config.atacTripUpdatesURL)
            let (vData, uData) = try await (vehiclesData, updatesData)

            let vehicleFeed = try TransitRealtime_FeedMessage(serializedBytes: vData)
            let updatesFeed = try TransitRealtime_FeedMessage(serializedBytes: uData)

            vehicles = decodeVehicles(vehicleFeed)
            let decoded = decodeTripUpdates(updatesFeed)
            stopPredictions = decoded.byStop
            tripStopTimes = decoded.byTrip
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private func decodeVehicles(_ feed: TransitRealtime_FeedMessage) -> [TransitVehicle] {
        feed.entity.compactMap { entity -> TransitVehicle? in
            guard entity.hasVehicle, entity.vehicle.hasPosition else { return nil }
            let vehiclePosition = entity.vehicle
            let routeId = vehiclePosition.hasTrip ? vehiclePosition.trip.routeID : ""
            let route = routeId.isEmpty ? nil : gtfsStore.route(for: routeId)
            let vehicleId = vehiclePosition.hasVehicle && vehiclePosition.vehicle.hasID
                ? vehiclePosition.vehicle.id
                : entity.id
            let tripId = vehiclePosition.hasTrip && vehiclePosition.trip.hasTripID ? vehiclePosition.trip.tripID : nil

            return TransitVehicle(
                id: "atac-\(vehicleId)",
                coordinate: CLLocationCoordinate2D(
                    latitude: Double(vehiclePosition.position.latitude),
                    longitude: Double(vehiclePosition.position.longitude)
                ),
                bearing: vehiclePosition.position.hasBearing ? Double(vehiclePosition.position.bearing) : nil,
                routeId: routeId.isEmpty ? nil : routeId,
                routeLabel: route?.routeShortName ?? (routeId.isEmpty ? nil : routeId),
                kind: route?.kind ?? .bus,
                transitOperator: route?.transitOperator ?? .atac,
                scope: .fullFleet,
                delaySeconds: nil,
                tripId: tripId
            )
        }
    }

    /// Single pass over `trip_updates` builds both indices: per-stop (for
    /// "what's coming to this stop") and per-trip (for "the full schedule
    /// of this specific vehicle's current run").
    private func decodeTripUpdates(_ feed: TransitRealtime_FeedMessage) -> (byStop: [String: [AtacStopPrediction]], byTrip: [String: [AtacTripStopTime]]) {
        var byStop: [String: [AtacStopPrediction]] = [:]
        var byTrip: [String: [AtacTripStopTime]] = [:]
        let now = Date()

        for entity in feed.entity {
            guard entity.hasTripUpdate else { continue }
            let tripUpdate = entity.tripUpdate
            let routeId = tripUpdate.hasTrip ? tripUpdate.trip.routeID : ""
            let route = routeId.isEmpty ? nil : gtfsStore.route(for: routeId)
            let tripId = tripUpdate.hasTrip && tripUpdate.trip.hasTripID ? tripUpdate.trip.tripID : entity.id

            for stopTimeUpdate in tripUpdate.stopTimeUpdate {
                guard stopTimeUpdate.hasStopID else { continue }
                let event: TransitRealtime_TripUpdate.StopTimeEvent?
                if stopTimeUpdate.hasArrival {
                    event = stopTimeUpdate.arrival
                } else if stopTimeUpdate.hasDeparture {
                    event = stopTimeUpdate.departure
                } else {
                    event = nil
                }
                guard let event, event.hasTime, event.time > 0 else { continue }

                let arrivalDate = Date(timeIntervalSince1970: TimeInterval(event.time))
                let delaySeconds = event.hasDelay ? Int(event.delay) : nil

                // The per-stop "what's coming next" list only makes sense
                // for the future; the full per-trip schedule below keeps
                // every stop so a tapped vehicle's whole run is visible,
                // past and future.
                if arrivalDate.timeIntervalSince(now) > -120 {
                    let prediction = AtacStopPrediction(
                        tripId: tripId,
                        routeId: routeId,
                        routeLabel: route?.routeShortName ?? routeId,
                        kind: route?.kind ?? .bus,
                        arrival: arrivalDate,
                        delaySeconds: delaySeconds,
                        headsign: gtfsStore.headsign(forTripId: tripId)
                    )
                    byStop[stopTimeUpdate.stopID, default: []].append(prediction)
                }

                let stopName = gtfsStore.stop(for: stopTimeUpdate.stopID)?.stopName ?? stopTimeUpdate.stopID
                byTrip[tripId, default: []].append(AtacTripStopTime(
                    stopId: stopTimeUpdate.stopID,
                    stopName: stopName,
                    sequence: stopTimeUpdate.hasStopSequence ? Int(stopTimeUpdate.stopSequence) : byTrip[tripId]?.count ?? 0,
                    arrival: arrivalDate,
                    delaySeconds: delaySeconds
                ))
            }
        }

        for key in byStop.keys {
            byStop[key]?.sort { $0.arrival < $1.arrival }
        }
        for key in byTrip.keys {
            byTrip[key]?.sort { $0.sequence < $1.sequence }
        }
        return (byStop, byTrip)
    }
}
