import Foundation
import ZIPFoundation

/// Owns Rome's urban static GTFS (Atac + Roma TPL combined): downloads +
/// caches it once, then serves viewport-scoped stop/line lookups for the
/// map layer. Loads independently of Cotral's own GTFS store — if Rome's
/// feed is ever unreachable, the app should still work fine for Cotral,
/// just without the urban overlay (graceful degradation, not a shared
/// failure domain).
@MainActor
final class AtacGtfsStore: ObservableObject {
    @Published private(set) var state: GTFSLoadingState = .idle
    /// 0...1 while `state == .downloading` and the response gave a content
    /// length; nil otherwise. The ~47MB zip (which includes `stop_times.txt`)
    /// is the one download in this app worth showing real progress for.
    @Published private(set) var downloadProgress: Double?

    private var stops: [AtacStop] = []
    private var stopById: [String: AtacStop] = [:]
    private var routes: [String: AtacRoute] = [:]
    private var shapes: [AtacLineShape] = []
    private var shapesByRouteId: [String: [AtacLineShape]] = [:]
    private var routeToStopIds: [String: Set<String>] = [:]
    /// Kept for `scheduledDepartures(forStopId:)`'s on-demand rescan of
    /// `stop_times.txt` — see `AtacGtfsParsing`'s header comment for why the
    /// full per-stop schedule itself isn't also kept in memory.
    private var tripToRoute: [String: String] = [:]
    private var tripToService: [String: String] = [:]
    private var activeServiceIdsByDate: [String: Set<String>] = [:]

    private let cacheDirectory: URL
    /// `stop_times.txt` (240MB/~5.1M rows) is included so exact route<->stop
    /// membership can be built (see `AtacGtfsParsing`) instead of the old
    /// geometry-distance approximation. Its cost is one-time and, in
    /// practice, free on top of what was already happening: the full zip
    /// (this file included) was already being downloaded in full just to
    /// pull out the smaller files, only the extraction+parsing step skipped
    /// it before. `calendar_dates.txt` is this feed's only calendar file (no
    /// `calendar.txt` at all) and is needed to know which service_ids from
    /// `stop_times.txt`/`trips.txt` actually run on a given day.
    private let requiredFiles = ["stops.txt", "routes.txt", "trips.txt", "shapes.txt", "stop_times.txt", "calendar_dates.txt"]
    private let session = URLSession(configuration: .ephemeral)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("AtacGTFS", isDirectory: true)
    }

    func ensureLoaded() async {
        guard state != .ready else { return }
        await load()
    }

    func retry() async {
        state = .idle
        await load()
    }

    private func load() async {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            if !requiredFilesExist() {
                state = .downloading
                let zipData = try await download(Config.atacGtfsZipURL, onProgress: reportDownloadProgress)
                downloadProgress = nil
                state = .extracting
                try extract(zipData: zipData)
            }

            state = .parsing
            let directory = cacheDirectory
            let parsed = try await Task.detached(priority: .userInitiated) {
                try AtacGtfsParsing.parseAll(in: directory)
            }.value

            stops = parsed.stops
            stopById = Dictionary(parsed.stops.map { ($0.stopId, $0) }, uniquingKeysWith: { _, latest in latest })
            routes = parsed.routes
            shapes = parsed.shapes
            shapesByRouteId = Dictionary(grouping: parsed.shapes, by: \.routeId)
            var invertedRouteToStopIds: [String: Set<String>] = [:]
            for (stopId, routeIds) in parsed.stopToRouteIds {
                for routeId in routeIds {
                    invertedRouteToStopIds[routeId, default: []].insert(stopId)
                }
            }
            routeToStopIds = invertedRouteToStopIds
            tripToRoute = parsed.tripToRoute
            tripToService = parsed.tripToService
            activeServiceIdsByDate = parsed.activeServiceIdsByDate
            state = .ready
        } catch {
            downloadProgress = nil
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func requiredFilesExist() -> Bool {
        requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent($0).path)
        }
    }

    /// `URLSession.data(for:)`/`data(for:delegate:)` never invoke
    /// `URLSessionDataDelegate`'s streaming callbacks at all — confirmed
    /// directly (file-based debug logging showed zero calls to
    /// `didReceive(data:)` across several delegate-signature variants,
    /// despite the download completing with the exact right byte count):
    /// Foundation's async convenience methods just return the final result
    /// and bypass the delegate for data events. `bytes(for:)` streams the
    /// response body directly instead, with no delegate involved, so
    /// progress can be computed as bytes actually arrive. `nonisolated` so
    /// the byte-by-byte loop (tens of millions of iterations for this
    /// ~47MB zip) doesn't tie up the main actor for the whole download.
    private nonisolated func download(_ url: URL, onProgress: @escaping (Double) -> Void) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = Config.gtfsDownloadTimeout
        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        } catch {
            throw GTFSError.download("Download dei dati Atac/Roma TPL fallito: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GTFSError.download("Download dei dati Atac/Roma TPL fallito.")
        }

        let expectedLength = response.expectedContentLength
        var data = Data()
        if expectedLength > 0 { data.reserveCapacity(Int(expectedLength)) }
        var lastReportedPercent = -1
        do {
            for try await byte in asyncBytes {
                data.append(byte)
                guard expectedLength > 0 else { continue }
                let percent = Int(Double(data.count) / Double(expectedLength) * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    onProgress(Double(data.count) / Double(expectedLength))
                }
            }
        } catch {
            throw GTFSError.download("Download dei dati Atac/Roma TPL fallito: \(error.localizedDescription)")
        }
        return data
    }

    /// Passed as `download`'s `onProgress` — called from the (nonisolated)
    /// byte-iteration loop, so this hops to MainActor before touching
    /// `@Published`.
    private nonisolated func reportDownloadProgress(_ fraction: Double) {
        Task { @MainActor in self.downloadProgress = fraction }
    }

    private func extract(zipData: Data) throws {
        let tempZip = cacheDirectory.appendingPathComponent("download.zip")
        try zipData.write(to: tempZip)
        defer { try? FileManager.default.removeItem(at: tempZip) }

        let archive: Archive
        do {
            archive = try Archive(url: tempZip, accessMode: .read)
        } catch {
            throw GTFSError.extraction("Archivio GTFS Atac/Roma TPL non valido o corrotto.")
        }

        let required = Set(requiredFiles)
        for entry in archive {
            let fileName = entry.path.split(separator: "/").last.map(String.init) ?? entry.path
            guard required.contains(fileName) else { continue }
            let destination = cacheDirectory.appendingPathComponent(fileName)
            _ = try archive.extract(entry, to: destination)
        }

        guard requiredFilesExist() else {
            throw GTFSError.extraction("File GTFS mancanti nell'archivio Atac/Roma TPL scaricato.")
        }
    }

    // MARK: - Viewport-scoped queries

    func stopsInRegion(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, limit: Int = 300) -> [AtacStop] {
        var results: [AtacStop] = []
        for stop in stops {
            if stop.lat >= minLat, stop.lat <= maxLat, stop.lon >= minLon, stop.lon <= maxLon {
                results.append(stop)
                if results.count >= limit { break }
            }
        }
        return results
    }

    func shapesInRegion(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, limit: Int = 150) -> [AtacLineShape] {
        var results: [AtacLineShape] = []
        for shape in shapes where shape.intersects(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon) {
            results.append(shape)
            if results.count >= limit { break }
        }
        return results
    }

    func route(for routeId: String) -> AtacRoute? {
        routes[routeId]
    }

    func stop(for stopId: String) -> AtacStop? {
        stopById[stopId]
    }

    /// All shapes for a line, regardless of the current map viewport — used
    /// when the user focuses on one line after tapping a vehicle, since its
    /// route can easily extend beyond whatever's currently on screen.
    func shapes(forRouteId routeId: String) -> [AtacLineShape] {
        shapesByRouteId[routeId] ?? []
    }

    /// Exact stops served by a line, from real GTFS route<->stop membership
    /// (`stop_times.txt`, parsed once in `AtacGtfsParsing`) — used when the
    /// user focuses on one line after tapping a vehicle or opening it from
    /// the Linee browser. Replaced an earlier point-to-line-segment
    /// distance heuristic that had to approximate this without
    /// `stop_times.txt`'s 240MB cost; now that it's parsed, this is a plain
    /// lookup with no approximation or false positives/negatives.
    func stopsForRoute(_ routeId: String) -> [AtacStop] {
        guard let stopIds = routeToStopIds[routeId] else { return [] }
        return stopIds.compactMap { stopById[$0] }.sorted { $0.stopName < $1.stopName }
    }

    /// Best-effort static-timetable fallback for a stop with no live
    /// `trip_updates` prediction at all — used by `AtacStopDetailSheet` only
    /// once it's confirmed the realtime feed has nothing for that stop.
    /// Scans today's (Rome time) active service_ids against a fresh,
    /// on-demand byte-scan of the cached `stop_times.txt` for just this one
    /// stop (see `AtacGtfsParsing.scheduledDepartures` for why this isn't
    /// precomputed for the whole network up front), so it's only as
    /// expensive as it needs to be: one full-file scan, run rarely, off the
    /// main thread. Doesn't handle a service that started "yesterday" and
    /// runs past midnight into this morning (GTFS times ≥24:00:00 under
    /// *today's* service_id already work fine here; a night run still under
    /// *yesterday's* service_id doesn't) — an acceptable gap for a
    /// last-resort estimate, not attempted here.
    func scheduledDepartures(forStopId stopId: String, limit: Int = 6) async throws -> [AtacStopPrediction] {
        guard state == .ready else { return [] }
        let directory = cacheDirectory
        let tripToRoute = self.tripToRoute
        let tripToService = self.tripToService
        let routesSnapshot = routes
        let romeCalendar = Self.romeCalendar
        let now = Date()
        let activeServiceIds = activeServiceIdsByDate[Self.dateKeyFormatter.string(from: now)] ?? []
        guard !activeServiceIds.isEmpty else { return [] }
        let midnight = romeCalendar.startOfDay(for: now)
        let nowSeconds = Int(now.timeIntervalSince(midnight))

        let raw = try await Task.detached(priority: .userInitiated) {
            try AtacGtfsParsing.scheduledDepartures(
                forStopId: stopId,
                in: directory.appendingPathComponent("stop_times.txt"),
                tripToRoute: tripToRoute,
                activeServiceIds: activeServiceIds,
                tripToService: tripToService
            )
        }.value

        return raw
            .filter { $0.departureSeconds >= nowSeconds }
            .sorted { $0.departureSeconds < $1.departureSeconds }
            .prefix(limit)
            .map { departure in
                let route = routesSnapshot[departure.routeId]
                return AtacStopPrediction(
                    tripId: departure.tripId,
                    routeId: departure.routeId,
                    routeLabel: route?.routeShortName ?? departure.routeId,
                    kind: route?.kind ?? .bus,
                    arrival: midnight.addingTimeInterval(TimeInterval(departure.departureSeconds)),
                    delaySeconds: nil,
                    isScheduled: true
                )
            }
    }

    private static let romeCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        return formatter
    }()

    // MARK: - Search

    func searchStops(query: String, limit: Int = 15) -> [AtacStop] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [AtacStop] = []
        for stop in stops where stop.stopName.lowercased().contains(q) {
            results.append(stop)
            if results.count >= limit { break }
        }
        return results
    }

    func searchRoutes(query: String, limit: Int = 10) -> [AtacRoute] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Array(
            routes.values
                .filter { $0.routeShortName.lowercased().contains(q) || $0.routeLongName.lowercased().contains(q) }
                .sorted { $0.routeShortName < $1.routeShortName }
                .prefix(limit)
        )
    }

    /// All routes, for the standalone "Linee" browser (grouped by kind
    /// there) — not viewport-scoped, since that screen has no map.
    func allRoutes() -> [AtacRoute] {
        Array(routes.values).sorted { $0.routeShortName < $1.routeShortName }
    }
}
