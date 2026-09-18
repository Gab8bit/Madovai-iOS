import Foundation

/// One stop along a specific Atac/Roma TPL trip's realtime-predicted
/// itinerary — the full "corsa corrente" schedule for a tapped vehicle,
/// built from the same `trip_updates` feed as `AtacStopPrediction`, just
/// indexed by trip instead of by stop.
struct AtacTripStopTime: Identifiable, Hashable {
    let stopId: String
    let stopName: String
    let sequence: Int
    let arrival: Date
    let delaySeconds: Int?

    var id: String { "\(stopId)-\(sequence)" }
}
