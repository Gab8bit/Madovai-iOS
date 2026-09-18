import CoreLocation
import Foundation

/// Pure, non-isolated CSV parsing for the four GTFS files we need, mirroring
/// the reference server's `gtfsService.ts` loaders field-for-field. Kept
/// free of any actor/MainActor isolation so it can run on a background
/// thread via `Task.detached` — `stop_times.txt` in particular can be large.
enum GTFSParsing {
    struct ParsedData {
        var stops: [GtfsStop]
        var stopById: [String: GtfsStop]
        var routes: [String: GtfsRoute]
        var stopToRouteIds: [String: Set<String>]
        /// Only ever non-empty for the rail feed — reuses `AtacLineShape`
        /// (a plain drawable-polyline model, nothing Atac-specific about
        /// its shape) since drawing a Cotral rail line's route on the map
        /// is otherwise identical to drawing an Atac one. Cotral's *bus*
        /// shapes are deliberately never parsed this way (a whole regional
        /// network vs. 3 short rail lines).
        var shapes: [AtacLineShape]
    }

    struct RailStopTime {
        let sequence: Int
        let stopId: String
        let departureSeconds: Int
    }

    /// GTFS calendar.txt weekday pattern. `weekdays` is Monday-first
    /// (index 0 = Monday … 6 = Sunday) to match how the column order in
    /// the file itself reads, not `Calendar`'s Sunday-first numbering —
    /// callers convert at the point of use (see `GTFSStore.scheduledDepartures`).
    struct GtfsCalendarService {
        let weekdays: [Bool]
        let startDate: Int
        let endDate: Int
    }

    /// Only ever populated for Cotral's *rail* feed — its `stop_times.txt`
    /// is a few hundred KB (3 lines, ~500 trips/day); the bus feed's
    /// equivalent is 175MB uncompressed and deliberately never parsed this
    /// way. This is what lets a Cotral rail station show a scheduled
    /// timetable even though the live PIV.do system has no data for it at
    /// all (see `PoleDetailViewModel`/`PoleDetailSheet`).
    struct RailSchedule {
        var tripStops: [String: [RailStopTime]]
        var tripService: [String: String]
        /// trip_id -> namespaced ("F:"-prefixed) route_id — lets
        /// `GTFSStore.stopsForRouteInOrder` find a trip that belongs to a
        /// given rail route and reuse its already-sequence-sorted
        /// `tripStops` entry as that route's physical station order.
        var tripRoute: [String: String]
        var calendarByService: [String: GtfsCalendarService]
        /// serviceId -> date(YYYYMMDD) -> added(true)/removed(false).
        var exceptionsByService: [String: [Int: Bool]]
    }

    /// - Parameter isRail: tags parsed stops/routes as coming from Cotral's
    ///   rail feed and namespaces route ids ("F:" prefix) so merging bus +
    ///   rail data can never collide two different routes under one id.
    ///   Stop ids are intentionally left un-namespaced (see `GtfsStop.isRail`).
    static func parseAll(in directory: URL, isRail: Bool) throws -> ParsedData {
        let routePrefix = isRail ? "F:" : ""
        let (stops, stopById) = try parseStops(directory.appendingPathComponent("stops.txt"), isRail: isRail)
        let routes = try parseRoutes(directory.appendingPathComponent("routes.txt"), isRail: isRail, routePrefix: routePrefix)
        let tripToRoute = try parseTrips(directory.appendingPathComponent("trips.txt"), routePrefix: routePrefix)
        let stopToRouteIds = try parseStopTimes(directory.appendingPathComponent("stop_times.txt"), tripToRoute: tripToRoute)
        let shapes = isRail ? try parseRailShapes(in: directory, routePrefix: routePrefix) : []
        return ParsedData(stops: stops, stopById: stopById, routes: routes, stopToRouteIds: stopToRouteIds, shapes: shapes)
    }

    /// Quote-aware CSV field split, mirroring the reference server's own
    /// hand-rolled `parseCsvLine` (handles `""` as an escaped quote inside
    /// a quoted field).
    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }

    private static func parseStops(_ url: URL, isRail: Bool) throws -> (stops: [GtfsStop], stopById: [String: GtfsStop]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        var stops: [GtfsStop] = []
        var stopById: [String: GtfsStop] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = parseCSVLine(trimmed)
            guard fields.count > 3 else { return }
            let stopName = GTFSTextUtils.stripTrailingHashCode(fields[1])
            let stop = GtfsStop(
                stopId: fields[0],
                stopName: stopName,
                stopNameLower: stopName.lowercased(),
                stopLat: Double(fields[2]) ?? 0,
                stopLon: Double(fields[3]) ?? 0,
                isRail: isRail
            )
            stops.append(stop)
            stopById[stop.stopId] = stop
        }
        return (stops, stopById)
    }

    private static func parseRoutes(_ url: URL, isRail: Bool, routePrefix: String) throws -> [String: GtfsRoute] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var routes: [String: GtfsRoute] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = parseCSVLine(trimmed)
            guard fields.count > 3 else { return }
            let id = routePrefix + fields[0]
            routes[id] = GtfsRoute(routeId: id, routeShortName: fields[2], routeLongName: fields[3], isRail: isRail)
        }
        return routes
    }

    /// trip_id -> (namespaced) route_id (GTFS trips.txt columns: route_id, service_id, trip_id, ...).
    private static func parseTrips(_ url: URL, routePrefix: String) throws -> [String: String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var tripToRoute: [String: String] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = parseCSVLine(trimmed)
            guard fields.count > 2 else { return }
            tripToRoute[fields[2]] = routePrefix + fields[0]
        }
        return tripToRoute
    }

    /// stop_times.txt can be huge, so this mirrors the reference server's
    /// own fast-path scan (trip_id, stop_id only — columns 0 and 3) instead
    /// of running the full quote-aware CSV parser per line.
    private static func parseStopTimes(_ url: URL, tripToRoute: [String: String]) throws -> [String: Set<String>] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var stopToRouteIds: [String: Set<String>] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine || line.isEmpty { return }
            let parts = line.split(separator: ",", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return }
            let tripId = String(parts[0]).replacingOccurrences(of: "\"", with: "")
            let stopId = String(parts[3]).replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            guard !stopId.isEmpty, let routeId = tripToRoute[tripId] else { return }
            stopToRouteIds[stopId, default: []].insert(routeId)
        }
        return stopToRouteIds
    }

    /// Rail-only: route↔shape association plus the shapes themselves, for
    /// drawing a rail line's route on the map — mirrors
    /// `AtacGtfsParsing.parseAll`'s shape handling, just for the 3 much
    /// smaller Cotral rail lines instead of Rome's whole bus/tram network.
    /// Missing `shapes.txt` (e.g. an install from before this existed, or a
    /// feed that ever ships without one) degrades to no line drawn, not an
    /// error — the rest of the rail feed still loads fine either way.
    private static func parseRailShapes(in directory: URL, routePrefix: String) throws -> [AtacLineShape] {
        let tripsURL = directory.appendingPathComponent("trips.txt")
        let shapesURL = directory.appendingPathComponent("shapes.txt")
        guard FileManager.default.fileExists(atPath: shapesURL.path) else { return [] }

        var routeToShapeIds: [String: Set<String>] = [:]
        let tripsContent = try String(contentsOf: tripsURL, encoding: .utf8)
        var isFirstLine = true
        tripsContent.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = parseCSVLine(trimmed)
            guard fields.count > 4, !fields[4].isEmpty else { return }
            routeToShapeIds[routePrefix + fields[0], default: []].insert(fields[4])
        }

        var pointsBySequence: [String: [(Int, CLLocationCoordinate2D)]] = [:]
        let shapesContent = try String(contentsOf: shapesURL, encoding: .utf8)
        isFirstLine = true
        shapesContent.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine || line.isEmpty { return }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 4,
                  let lat = Double(parts[1]), let lon = Double(parts[2]),
                  let sequence = Int(parts[3])
            else { return }
            pointsBySequence[String(parts[0]), default: []].append((sequence, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }

        var shapes: [AtacLineShape] = []
        for (routeId, shapeIds) in routeToShapeIds {
            for shapeId in shapeIds {
                guard let points = pointsBySequence[shapeId]?.sorted(by: { $0.0 < $1.0 }).map(\.1), points.count > 1 else { continue }
                shapes.append(AtacLineShape(shapeId: shapeId, routeId: routeId, coordinates: points))
            }
        }
        return shapes
    }

    /// Rail-only: unlike `parseStopTimes` above (which discards everything
    /// but trip_id/stop_id to stay cheap on the 175MB bus file), this reads
    /// arrival/departure time and stop_sequence too, plus trip->service and
    /// calendar/calendar_dates — everything needed to answer "what are
    /// today's scheduled departures from this rail stop". Only ever called
    /// against Cotral's rail directory, whose `stop_times.txt` is ~380KB.
    /// Returns nil if `stop_times.txt`/`trips.txt` aren't present (should
    /// only happen if extraction failed); `calendar.txt`/`calendar_dates.txt`
    /// are optional GTFS files and are simply left empty if absent.
    static func parseRailSchedule(in directory: URL) throws -> RailSchedule? {
        let stopTimesURL = directory.appendingPathComponent("stop_times.txt")
        let tripsURL = directory.appendingPathComponent("trips.txt")
        guard FileManager.default.fileExists(atPath: stopTimesURL.path),
              FileManager.default.fileExists(atPath: tripsURL.path) else { return nil }

        var tripService: [String: String] = [:]
        var tripRoute: [String: String] = [:]
        let tripsContent = try String(contentsOf: tripsURL, encoding: .utf8)
        var isFirstLine = true
        tripsContent.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = parseCSVLine(trimmed)
            guard fields.count > 2 else { return }
            tripService[fields[2]] = fields[1]
            // This function is only ever called against the rail directory
            // (see its doc comment), so the "F:" namespace `parseTrips`
            // would otherwise apply via `routePrefix` is hardcoded here too
            // — matches the ids `GTFSStore`'s rail `GtfsRoute`s actually use.
            tripRoute[fields[2]] = "F:" + fields[0]
        }

        var tripStops: [String: [RailStopTime]] = [:]
        let stopTimesContent = try String(contentsOf: stopTimesURL, encoding: .utf8)
        isFirstLine = true
        stopTimesContent.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = parseCSVLine(trimmed)
            guard fields.count > 4,
                  let departureSeconds = parseGtfsTimeToSeconds(fields[2]),
                  let sequence = Int(fields[4]) else { return }
            let tripId = fields[0]
            let stopId = fields[3]
            tripStops[tripId, default: []].append(RailStopTime(sequence: sequence, stopId: stopId, departureSeconds: departureSeconds))
        }
        for key in tripStops.keys {
            tripStops[key]?.sort { $0.sequence < $1.sequence }
        }

        var calendarByService: [String: GtfsCalendarService] = [:]
        let calendarURL = directory.appendingPathComponent("calendar.txt")
        if let calendarContent = try? String(contentsOf: calendarURL, encoding: .utf8) {
            isFirstLine = true
            calendarContent.enumerateLines { line, _ in
                defer { isFirstLine = false }
                if isFirstLine { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let fields = parseCSVLine(trimmed)
                guard fields.count > 9 else { return }
                let weekdays = (1...7).map { fields[$0] == "1" }
                guard let start = Int(fields[8]), let end = Int(fields[9]) else { return }
                calendarByService[fields[0]] = GtfsCalendarService(weekdays: weekdays, startDate: start, endDate: end)
            }
        }

        var exceptionsByService: [String: [Int: Bool]] = [:]
        let exceptionsURL = directory.appendingPathComponent("calendar_dates.txt")
        if let exceptionsContent = try? String(contentsOf: exceptionsURL, encoding: .utf8) {
            isFirstLine = true
            exceptionsContent.enumerateLines { line, _ in
                defer { isFirstLine = false }
                if isFirstLine { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                let fields = parseCSVLine(trimmed)
                guard fields.count > 2, let date = Int(fields[1]) else { return }
                exceptionsByService[fields[0], default: [:]][date] = (fields[2] == "1")
            }
        }

        return RailSchedule(tripStops: tripStops, tripService: tripService, tripRoute: tripRoute, calendarByService: calendarByService, exceptionsByService: exceptionsByService)
    }

    private static func parseGtfsTimeToSeconds(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}
