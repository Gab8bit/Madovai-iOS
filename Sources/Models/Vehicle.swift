/// The vehicle assigned to a transit, nested in `Transit.automezzo`.
struct Vehicle: Codable, Hashable {
    /// Vehicle code used for /vehiclerealtimepositions/{vehicleCode}. Absent when no
    /// vehicle is assigned to this run.
    var codice: String?
    /// Whether this specific vehicle is currently transmitting live position updates.
    var isAlive: Bool?
}
