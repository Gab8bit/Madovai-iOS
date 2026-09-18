import Foundation
import ZIPFoundation

enum GTFSLoadingState: Equatable {
    case idle
    case downloading
    case extracting
    case parsing
    case ready
    case failed(String)
}

enum GTFSError: Error, LocalizedError {
    case download(String)
    case extraction(String)

    var errorDescription: String? {
        switch self {
        case .download(let message), .extraction(let message): return message
        }
    }
}

/// Owns Cotral's static GTFS feeds — bus (GTFS_COTRAL) and rail
/// (GTFS_FERRO) — on-device: downloads + caches them once, then serves the
/// same lookups the reference server's `gtfsService.ts` does (nearby poles,
/// locality/stop/line search, destination matching) — this is the
/// *primary* source for anything that isn't inherently real-time.
@MainActor
final class GTFSStore: ObservableObject {
    @Published private(set) var state: GTFSLoadingState = .idle
    /// 0...1 while `state == .downloading` and the response gave a content
    /// length; nil otherwise (including mid-download if the server didn't
    /// report a length) — the loading banner falls back to an indeterminate
    /// spinner when nil.
    @Published private(set) var downloadProgress: Double?

    private var stops: [GtfsStop] = []
    private var stopById: [String: GtfsStop] = [:]
    private var routes: [String: GtfsRoute] = [:]
    private var stopToRouteIds: [String: Set<String>] = [:]
    private var routeToStopIds: [String: Set<String>] = [:]
    private var railSchedule: GTFSParsing.RailSchedule?
    private var shapesByRouteId: [String: [AtacLineShape]] = [:]

    private let cacheDirectory: URL
    private let requiredFiles = ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt"]
    /// Optional (not gated by `requiredFilesExist`) — `calendar.txt`/
    /// `calendar_dates.txt` build `railSchedule` (rail-only; GTFS allows
    /// either to be legitimately absent, so these are best-effort),
    /// `shapes.txt` (rail-only too) draws a focused rail line's route on
    /// the map. Grabbed opportunistically whenever present in whatever
    /// archive was just extracted.
    private let optionalScheduleFiles = ["calendar.txt", "calendar_dates.txt", "shapes.txt"]

    private let session = URLSession(configuration: .ephemeral)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("GTFS", isDirectory: true)
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
            let busDir = cacheDirectory.appendingPathComponent("bus", isDirectory: true)
            let railDir = cacheDirectory.appendingPathComponent("rail", isDirectory: true)
            try FileManager.default.createDirectory(at: busDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: railDir, withIntermediateDirectories: true)

            if !requiredFilesExist(in: busDir) {
                state = .downloading
                let zipData = try await download(Config.gtfsBusZipURL, onProgress: reportDownloadProgress)
                downloadProgress = nil
                state = .extracting
                try extract(zipData: zipData, into: busDir)
            }

            // Rail feed is a nice-to-have — if it's ever missing/malformed,
            // degrade to bus-only rather than blocking the whole app.
            //
            // Also re-fetch (self-healing, no reinstall needed) if a rail
            // dir survives from before the rail-schedule/shape features
            // existed: `calendar.txt`/`shapes.txt` weren't in `requiredFiles`
            // when that cache was written, so they'd otherwise sit there
            // forever missing and `scheduledDepartures`/`shapes(forRouteId:)`
            // would silently stay empty. Not gating on `calendar_dates.txt`
            // too — that one's genuinely optional per the GTFS spec, and
            // gating a redownload on a file that could be legitimately
            // absent risks looping every launch. The rail zip is tiny
            // (~500KB) so redoing this once is cheap.
            var railAvailable = requiredFilesExist(in: railDir)
                && FileManager.default.fileExists(atPath: railDir.appendingPathComponent("calendar.txt").path)
                && FileManager.default.fileExists(atPath: railDir.appendingPathComponent("shapes.txt").path)
            if !railAvailable {
                do {
                    state = .downloading
                    let zipData = try await download(Config.gtfsRailZipURL, onProgress: reportDownloadProgress)
                    downloadProgress = nil
                    state = .extracting
                    try extract(zipData: zipData, into: railDir)
                    railAvailable = requiredFilesExist(in: railDir)
                } catch {
                    railAvailable = false
                }
            }

            downloadProgress = nil
            state = .parsing
            let parsedBus = try await Task.detached(priority: .userInitiated) {
                try GTFSParsing.parseAll(in: busDir, isRail: false)
            }.value
            let parsedRail = railAvailable ? try? await Task.detached(priority: .userInitiated) {
                try GTFSParsing.parseAll(in: railDir, isRail: true)
            }.value : nil
            railSchedule = railAvailable ? try? await Task.detached(priority: .userInitiated) {
                try GTFSParsing.parseRailSchedule(in: railDir)
            }.value : nil

            merge(bus: parsedBus, rail: parsedRail)
            state = .ready
        } catch {
            downloadProgress = nil
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func merge(bus: GTFSParsing.ParsedData, rail: GTFSParsing.ParsedData?) {
        var mergedStops = bus.stops
        var mergedStopById = bus.stopById
        var mergedRoutes = bus.routes
        var mergedStopToRouteIds = bus.stopToRouteIds

        if let rail {
            mergedStops.append(contentsOf: rail.stops)
            mergedStopById.merge(rail.stopById) { _, rail in rail }
            mergedRoutes.merge(rail.routes) { _, rail in rail }
            mergedStopToRouteIds.merge(rail.stopToRouteIds) { bus, rail in bus.union(rail) }
        }

        stops = mergedStops
        stopById = mergedStopById
        routes = mergedRoutes
        stopToRouteIds = mergedStopToRouteIds
        shapesByRouteId = Dictionary(grouping: rail?.shapes ?? [], by: \.routeId)

        var inverted: [String: Set<String>] = [:]
        for (stopId, routeIds) in stopToRouteIds {
            for routeId in routeIds {
                inverted[routeId, default: []].insert(stopId)
            }
        }
        routeToStopIds = inverted
    }

    private func requiredFilesExist(in directory: URL) -> Bool {
        requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
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
    /// progress can be computed as bytes actually arrive.
    /// `nonisolated` so the byte-by-byte loop below (tens of millions of
    /// iterations for Atac's ~47MB zip) doesn't tie up the main actor for
    /// the whole download — `session` is an immutable, safely-Sendable
    /// stored property, and `onProgress` hops back to MainActor itself.
    private nonisolated func download(_ url: URL, onProgress: @escaping (Double) -> Void) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = Config.gtfsDownloadTimeout
        let asyncBytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (asyncBytes, response) = try await session.bytes(for: request)
        } catch {
            throw GTFSError.download("Download dei dati GTFS fallito: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GTFSError.download("Download dei dati GTFS fallito.")
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
            throw GTFSError.download("Download dei dati GTFS fallito: \(error.localizedDescription)")
        }
        return data
    }

    /// Passed as `download`'s `onProgress` — called from the (nonisolated)
    /// byte-iteration loop, so this hops to MainActor before touching
    /// `@Published`.
    private nonisolated func reportDownloadProgress(_ fraction: Double) {
        Task { @MainActor in self.downloadProgress = fraction }
    }

    private func extract(zipData: Data, into directory: URL) throws {
        let tempZip = directory.appendingPathComponent("download.zip")
        try zipData.write(to: tempZip)
        defer { try? FileManager.default.removeItem(at: tempZip) }

        let archive: Archive
        do {
            archive = try Archive(url: tempZip, accessMode: .read)
        } catch {
            throw GTFSError.extraction("Archivio GTFS non valido o corrotto.")
        }

        let wanted = Set(requiredFiles).union(optionalScheduleFiles)
        for entry in archive {
            let fileName = entry.path.split(separator: "/").last.map(String.init) ?? entry.path
            guard wanted.contains(fileName) else { continue }
            let destination = directory.appendingPathComponent(fileName)
            _ = try archive.extract(entry, to: destination)
        }

        guard requiredFilesExist(in: directory) else {
            throw GTFSError.extraction("File GTFS mancanti nell'archivio scaricato.")
        }
    }

    // MARK: - Queries (mirroring gtfsService.ts, extended with stop/line search)

    func findStopsByPosition(latitude: Double, longitude: Double, range: Double, limit: Int = 40) -> [GtfsStop] {
        var results: [GtfsStop] = []
        for stop in stops {
            if stop.stopLat >= latitude - range, stop.stopLat <= latitude + range,
               stop.stopLon >= longitude - range, stop.stopLon <= longitude + range {
                results.append(stop)
                if results.count >= limit { break }
            }
        }
        return results
    }

    func findStopsInRegion(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, limit: Int = 60) -> [GtfsStop] {
        var results: [GtfsStop] = []
        for stop in stops {
            if stop.stopLat >= minLat, stop.stopLat <= maxLat, stop.stopLon >= minLon, stop.stopLon <= maxLon {
                results.append(stop)
                if results.count >= limit { break }
            }
        }
        return results
    }

    func findStopById(_ stopId: String) -> GtfsStop? {
        stopById[stopId]
    }

    /// Direct stop/station name search (e.g. "Termini", "Cassino") — more
    /// precise than locality search when you already know where you're going.
    func searchStops(query: String, limit: Int = 15) -> [GtfsStop] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var results: [GtfsStop] = []
        for stop in stops where stop.stopNameLower.contains(q) {
            results.append(stop)
            if results.count >= limit { break }
        }
        return results
    }

    /// Line/route search by number or name (e.g. "053", "Frosinone").
    func searchRoutes(query: String, limit: Int = 10) -> [GtfsRoute] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Array(
            routes.values
                .filter { $0.routeShortName.lowercased().contains(q) || $0.routeLongName.lowercased().contains(q) }
                .sorted { $0.routeShortName < $1.routeShortName }
                .prefix(limit)
        )
    }

    /// All stops served by a given (namespaced) route id.
    func stopsForRoute(_ routeId: String) -> [GtfsStop] {
        guard let stopIds = routeToStopIds[routeId] else { return [] }
        return stopIds.compactMap { stopById[$0] }
    }

    /// Same stops as `stopsForRoute`, but in physical line order instead of
    /// alphabetical — for a rail route, reuses the longest trip belonging to
    /// it (most likely to cover every station, in case some trips
    /// short-turn partway down the line) and its own already
    /// sequence-sorted `RailStopTime`s. Falls back to `stopsForRoute` as-is
    /// (alphabetical) when there's no rail schedule loaded or no trip found
    /// for this route — e.g. a bus route, which has no such sequence data
    /// parsed at all (see `GTFSParsing`'s header comment on why the bus
    /// feed's `stop_times.txt` is never read this way).
    func stopsForRouteInOrder(_ routeId: String) -> [GtfsStop] {
        guard let schedule = railSchedule else { return stopsForRoute(routeId) }
        // Sorted by trip id first so a tie on stop count (e.g. both
        // directions of the line covering all stations) resolves the same
        // way on every launch instead of whichever trip a `Dictionary`
        // happens to enumerate first that run.
        let matchingTrips = schedule.tripStops
            .filter { schedule.tripRoute[$0.key] == routeId }
            .sorted { $0.key < $1.key }
        guard let longest = matchingTrips.max(by: { $0.value.count < $1.value.count }) else {
            return stopsForRoute(routeId)
        }
        return longest.value.compactMap { stopById[$0.stopId] }
    }

    /// Rail lines only ("F:"-namespaced) — the standalone "Linee" browser's
    /// Cotral bucket. The ~4000 bus routes are deliberately left out there:
    /// with no per-line live vehicle data for Cotral (see
    /// `TransitVehicle.VisibilityScope`), a flat list that size wouldn't be
    /// very useful and would dominate the screen.
    func allRailRoutes() -> [GtfsRoute] {
        routes.values.filter { $0.routeId.hasPrefix("F:") }.sorted { $0.routeShortName < $1.routeShortName }
    }

    func getRoutesForStop(_ stopId: String) -> [GtfsRoute] {
        guard let routeIds = stopToRouteIds[stopId] else { return [] }
        return routeIds.compactMap { routes[$0] }
    }

    func route(for routeId: String) -> GtfsRoute? {
        routes[routeId]
    }

    /// A rail line's own drawable route, for the map — empty for any bus
    /// route (shapes are rail-only, see `GTFSParsing.parseRailShapes`).
    func shapes(forRouteId routeId: String) -> [AtacLineShape] {
        shapesByRouteId[routeId] ?? []
    }

    func getDestinationsFromRoutes(_ stopRoutes: [GtfsRoute]) -> [String] {
        var set = Set<String>()
        for route in stopRoutes {
            let name = GTFSTextUtils.stripTrailingHashCode(route.routeLongName)
            let parts = name.components(separatedBy: " - ")
            if parts.count >= 2, let last = parts.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty {
                set.insert(last)
            }
        }
        return set.sorted()
    }

    /// Today's remaining scheduled (static, non-live) departures from a
    /// Cotral rail stop, e.g. "RL_ACILIA". Resolves which GTFS calendar
    /// service(s) run today (weekday pattern in calendar.txt, overridden per
    /// date by calendar_dates.txt when present) and returns every trip that
    /// stops there under an active service, sorted by time. Returns nil only
    /// when no rail schedule was loaded at all (rail feed unavailable);
    /// returns an empty array when the schedule loaded fine but nothing
    /// happens to depart from this stop today.
    func scheduledDepartures(forRailStopId stopId: String, from date: Date = Date(), calendar: Calendar = .current) -> [GtfsScheduledDeparture]? {
        guard let schedule = railSchedule else { return nil }

        let todayInt = Self.yyyymmdd(from: date, calendar: calendar)
        let swiftWeekday = calendar.component(.weekday, from: date) // 1 = Sunday ... 7 = Saturday
        let mondayFirstIndex = (swiftWeekday + 5) % 7 // 0 = Monday ... 6 = Sunday, matching GTFS calendar.txt column order

        func isServiceActive(_ serviceId: String) -> Bool {
            if let override = schedule.exceptionsByService[serviceId]?[todayInt] {
                return override
            }
            guard let service = schedule.calendarByService[serviceId],
                  todayInt >= service.startDate, todayInt <= service.endDate else { return false }
            return service.weekdays[mondayFirstIndex]
        }

        var results: [GtfsScheduledDeparture] = []
        for (tripId, stopTimes) in schedule.tripStops {
            guard let serviceId = schedule.tripService[tripId], isServiceActive(serviceId) else { continue }
            guard let departure = stopTimes.first(where: { $0.stopId == stopId }) else { continue }
            guard let destinationStopId = stopTimes.last?.stopId,
                  let destinationStop = stopById[destinationStopId] else { continue }
            results.append(GtfsScheduledDeparture(tripId: tripId, destinationStopName: destinationStop.stopName, departureSeconds: departure.departureSeconds))
        }
        return results.sorted { $0.departureSeconds < $1.departureSeconds }
    }

    private static func yyyymmdd(from date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }
}
