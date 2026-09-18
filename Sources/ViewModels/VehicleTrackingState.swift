import Foundation

enum VehicleTrackingState: Equatable {
    /// Not following any vehicle right now.
    case idle
    /// Actively polling and receiving fresh positions.
    case tracking
    /// The user asked to follow a vehicle, but it stopped transmitting —
    /// surfaced explicitly instead of leaving the marker silently frozen.
    case lost(lastUpdate: Date?)
}
