import Foundation

/// App-wide configuration.
///
/// Since 2.0 every piece of data comes from the Madovai backend
/// (Madovai-Backend, `https://madovai.gab8bit.net/api/v1`, documented in its
/// `docs/API.md`): the app no longer downloads GTFS archives, decodes
/// GTFS-Realtime protobuf, parses Cotral's XML or talks to ASTRAL itself.
/// Polling intervals and thresholds mirror the web app (Madovai-Web
/// `services.js`), which is the reference client for the same API.
enum Config {

    /// Base URL of the backend's versioned API. Can be overridden at build
    /// time with the `MadovaiAPIBaseURL` Info.plist key (e.g. to point a
    /// test build at a server on the local network) without code changes.
    static let apiBaseURL: URL = {
        // Launch argument `-MadovaiAPIBaseURL <url>` (UI tests point the app
        // at an unreachable server this way), then the Info.plist key.
        let override = UserDefaults.standard.string(forKey: "MadovaiAPIBaseURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "MadovaiAPIBaseURL") as? String
        if let raw = override,
           let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), url.scheme != nil {
            return url
        }
        return URL(string: "https://madovai.gab8bit.net/api/v1")!
    }()

    /// `GET /health` lives at the server root, not under `/api/v1`.
    static var healthURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.path = "/health"
        components.query = nil
        return components.url!
    }

    /// Timeout for a single API request.
    static let requestTimeout: TimeInterval = 15

    /// How often an open stop/station sheet refreshes its departures.
    static let transitsPollInterval: TimeInterval = 15

    /// How often a followed Cotral vehicle's position is refreshed.
    static let vehiclePositionPollInterval: TimeInterval = 12

    /// Consecutive failed/empty position polls before live tracking is
    /// reported as lost (instead of leaving a frozen marker looking live).
    static let vehicleTrackingLossThreshold = 2

    /// The whole Atac/Roma TPL fleet (one call, server-side cache of 5 s).
    static let atacFleetPollInterval: TimeInterval = 15

    /// Cotral vehicles near the visible poles (server-side fan-out).
    static let cotralViewportVehiclePollInterval: TimeInterval = 18

    /// The backend accepts at most 15 poles per `cotral-vehicles` call.
    static let cotralViewportPoleQueryLimit = 15

    /// The backend accepts at most 150 stops per `atac-live` call.
    static let atacLiveStopLimit = 150

    /// Debounce after a map gesture ends before stops/lines are reloaded.
    static let viewportSettleDelay: TimeInterval = 0.45

    /// Only show the "Caricamento dati…" banner when a request is actually
    /// slow — no flicker on a fast connection.
    static let slowRequestHintDelay: TimeInterval = 0.4

    /// Below this zoom level stops and line shapes aren't loaded at all: a
    /// regional viewport would drown in thousands of markers (same threshold
    /// as the web app's `MIN_DATA_ZOOM`).
    static let minDataZoom: Double = 13

    /// Below this zoom level ambient vehicles aren't drawn (the whole city's
    /// ~1000 vehicles at once is unreadable and slows MapKit down); a focused
    /// line still shows its own vehicles at any zoom.
    static let minVehicleZoom: Double = 11

    /// From this zoom level vehicles are drawn as labelled badges; below it
    /// as small dots (same idea as the web app's `.zoom-low`).
    static let vehicleBadgeZoom: Double = 14
}
