import Foundation

/// Human-readable names for Rome's 4 metro lines — Roma Servizi per la
/// Mobilità's GTFS feed leaves `route_long_name` blank for all 4 (confirmed
/// directly against the real `routes.txt`, not something the app is
/// discarding), so there's genuinely no name to fall back on. Hand-written
/// mapping, same pattern as `CotralTrainRoute` for Cotral's rail lines.
/// `routeId` and `routeShortName` are identical literal strings in this feed
/// ("MEA", "MEB", "MEB1", "MEC" — confirmed against the real `routes.txt`).
enum AtacMetroLine: String, CaseIterable {
    case a = "MEA"
    case b = "MEB"
    case b1 = "MEB1"
    case c = "MEC"

    init?(routeShortName: String) {
        self.init(rawValue: routeShortName.uppercased())
    }

    var friendlyName: String {
        switch self {
        case .a: return "Metro A"
        case .b: return "Metro B"
        case .b1: return "Metro B1"
        case .c: return "Metro C"
        }
    }
}

extension AtacRoute {
    /// "Metro A" for a metro line, otherwise the existing long-name-with-
    /// short-name-fallback used throughout the app for buses/trams.
    var friendlyName: String {
        if let metro = AtacMetroLine(routeShortName: routeShortName) { return metro.friendlyName }
        return routeLongName.isEmpty ? routeShortName : routeLongName
    }

    /// `friendlyName` qualified with a direction, e.g. "Metro A verso
    /// Anagnina" — only when a specific direction/headsign is actually
    /// known (a bare line browse entry with no direction selected should
    /// just show `friendlyName` alone).
    func displayName(direction headsign: String?) -> String {
        guard let headsign, !headsign.isEmpty else { return friendlyName }
        return "\(friendlyName) verso \(headsign)"
    }
}
