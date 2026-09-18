import Foundation

/// App-wide configuration for CotralLive.
///
/// The app talks directly to Cotral's own internal live-data endpoint (the
/// same undocumented one `packages/server` in github.com/ChromuSx/cotral
/// proxies — discovered there via reverse engineering, not published by
/// Cotral) plus Cotral's public static GTFS feed. There is no middleman
/// server: everything the Node backend used to do (XML parsing, GTFS
/// lookups, coordinate normalization) happens on-device.
enum Config {

    /// Cotral's internal live-data endpoint. Plain HTTP — see the matching
    /// ATS exception in project.yml (`NSExceptionDomains`).
    static let cotralBaseURL = URL(string: "http://travel.mob.cotralspa.it:7777/beApp")!

    /// Shared client id used for the endpoints that require one (PIV.do
    /// cmd=1/cmd=6, Automezzi.do). This is the default value published in
    /// ChromuSx/cotral's own (MIT-licensed) server config — reused here for
    /// the same personal, non-commercial use that project itself targets.
    /// If Cotral ever invalidates it, check that repo for an updated value.
    static let cotralUserId = "1BB73DCDAFA007572FC51E7407AB497C"

    /// Look-ahead window (minutes) for transit queries, matching the
    /// reference server's own default.
    static let cotralDelta = "261"

    /// Cotral's public static GTFS feeds (stops/routes/trips/stop_times),
    /// used for pole/stop/line lookup and search. Both are the official
    /// links from cotralspa.it/open-data/ — plain HTTP on the same
    /// already-trusted host/port as the live endpoint above, which avoids
    /// the TLS certificate mismatch on travel.mob.cotralspa.it:4443 (that
    /// host's cert SAN is `*.cotralspa.it`, which doesn't literally cover
    /// the two-level `travel.mob.cotralspa.it` — verified with `curl -v`).
    static let gtfsBusZipURL = URL(string: "http://travel.mob.cotralspa.it:7777/GTFS/GTFS_COTRAL.zip")!
    static let gtfsRailZipURL = URL(string: "http://travel.mob.cotralspa.it:7777/GTFS/GTFS_FERRO.zip")!

    /// Cotral's train-schedule widget endpoint — a separate WordPress-hosted
    /// backend (`cotralspa.it`, HTTPS, no ATS exception needed), unrelated
    /// to `cotralBaseURL` above. See `CotralTrainScheduleClient`.
    static let cotralTrainScheduleBaseURL = URL(string: "https://cotralspa.it/wp-json/cotral/v1/get-train-stopsroute")!

    /// Timeout for a single network request.
    static let requestTimeout: TimeInterval = 15

    /// Timeout for the (much larger) GTFS zip download.
    static let gtfsDownloadTimeout: TimeInterval = 120

    /// How often the bottom sheet refreshes the transits list while open.
    static let transitsPollInterval: TimeInterval = 15

    /// How often we re-fetch a followed vehicle's live position.
    static let vehiclePositionPollInterval: TimeInterval = 12

    /// Consecutive failed/empty vehicle-position polls before we consider
    /// live tracking lost and surface that to the user instead of leaving
    /// the marker silently frozen.
    static let vehicleTrackingLossThreshold = 2

    /// Default search radius (in degrees) for "poles near me" and when
    /// jumping to a searched locality, matching the reference server's own
    /// GTFS bounding-box query.
    static let nearbyPolesRangeDegrees: Double = 0.01

    // MARK: - Roma Servizi per la Mobilità (Atac / Roma TPL urban transit)

    /// Static GTFS for Rome's urban network (Atac + Roma TPL combined),
    /// published by Roma Servizi per la Mobilità under CC-BY 3.0 Italia.
    static let atacGtfsZipURL = URL(string: "https://romamobilita.it/sites/default/files/rome_static_gtfs.zip")!

    /// GTFS-Realtime (protobuf) feeds, same license/source.
    static let atacVehiclePositionsURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_vehicle_positions_feed.pb")!
    static let atacTripUpdatesURL = URL(string: "https://romamobilita.it/sites/default/files/rome_rtgtfs_trip_updates_feed.pb")!

    /// How often the map re-polls the Atac/Roma TPL realtime feeds.
    static let atacRealtimePollInterval: TimeInterval = 18

    /// How far (in degrees) around the current map viewport to render Atac
    /// stops/line shapes — Rome's urban network is far too dense (thousands
    /// of stops, hundreds of overlapping shapes) to draw all at once.
    static let atacViewportPaddingDegrees: Double = 0.01

    /// Debounce before re-querying Cotral transits / re-filtering Atac
    /// stops+shapes after the map viewport changes, so a drag/zoom gesture
    /// doesn't fire a request per frame.
    static let viewportSettleDelay: TimeInterval = 0.6

    /// How often the opportunistic Cotral viewport vehicle scan refreshes.
    static let cotralViewportVehiclePollInterval: TimeInterval = 18

    /// Cap on how many currently-visible Cotral poles get queried per
    /// viewport scan, to keep the opportunistic vehicle lookup from firing
    /// dozens of requests at once in a dense area.
    static let cotralViewportPoleQueryLimit = 15
}
