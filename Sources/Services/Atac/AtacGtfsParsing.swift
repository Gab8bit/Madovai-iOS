import CoreLocation
import Foundation

/// Pure, non-isolated CSV parsing for Rome's urban GTFS (Atac + Roma TPL
/// combined), run off the main thread via `Task.detached` — `shapes.txt`
/// and `trips.txt` are both in the hundreds of thousands of rows for a
/// whole metropolitan network, and `stop_times.txt` is 240MB / ~5.1M rows.
///
/// `stop_times.txt` is parsed *only* to build exact route<->stop membership
/// (`stopToRouteIds` below) at load time — not for schedule times, since the
/// realtime `trip_updates` feed already gives genuinely live per-stop
/// predictions directly (see `AtacRealtimeService`). This membership parse
/// was deliberately skipped for a long time given the file's size, in favor
/// of a point-to-line-segment distance heuristic
/// (`AtacGtfsStore.stopsNearShapes`, since removed) — reinstated once
/// confirmed the cost is one-time (the full zip, including
/// `stop_times.txt`, was already being downloaded and cached either way;
/// only the extraction+parsing of this one file was being skipped).
///
/// A stop with no active realtime update *does* get a best-effort fallback,
/// though: `scheduledDepartures(forStopId:...)` below does a second,
/// on-demand byte-scan of the same cached `stop_times.txt` file for just
/// that one stop, only when a stop detail sheet actually needs it (a live
/// update never arrived) — deliberately not folded into the eager
/// `parseAll` pass, since keeping a full per-stop-per-trip schedule for the
/// whole network in memory at all times (~5.1M rows) would be a needless
/// permanent memory cost for a fallback that's the exception, not the rule.
enum AtacGtfsParsing {
    struct ParsedStatic {
        var stops: [AtacStop]
        var routes: [String: AtacRoute]
        var routeToShapeIds: [String: Set<String>]
        var shapes: [AtacLineShape]
        var stopToRouteIds: [String: Set<String>]
        /// Kept (unlike stop_times' own contents) since they're small
        /// (one entry per trip, short ids) and needed later by
        /// `scheduledDepartures(forStopId:...)` to resolve a matched
        /// stop_times row's trip back to a route + calendar service.
        var tripToRoute: [String: String]
        var tripToService: [String: String]
        /// trip_id -> cleaned trip_headsign (e.g. "Anagnina") — lets a
        /// specific vehicle/trip's own direction be shown (see
        /// `AtacGtfsStore.headsign(forTripId:)`).
        var tripToHeadsign: [String: String]
        /// "routeId|stopId" -> cleaned trip_headsign of the trips of that
        /// route serving that stop — a physical platform stop_id almost
        /// always serves one consistent direction for a given route (that's
        /// exactly why two "duplicate-looking" stops with the same name are
        /// really two different platforms), so this is a stable per-station,
        /// per-direction label (see `AtacGtfsStore.headsign(forRouteId:stopId:)`).
        var stopHeadsignByRoute: [String: String]
        /// "yyyyMMdd" -> service_ids running that day. This feed ships
        /// `calendar_dates.txt` with no `calendar.txt` at all — i.e. it's
        /// used in "explicit full list" mode (every active service day is
        /// its own row, exception_type is always 1/added), not as
        /// exceptions to a weekly pattern, confirmed against the real file.
        var activeServiceIdsByDate: [String: Set<String>]
    }

    static func parseAll(in directory: URL) throws -> ParsedStatic {
        let stops = try parseStops(directory.appendingPathComponent("stops.txt"))
        let routes = try parseRoutes(directory.appendingPathComponent("routes.txt"))
        let (routeToShapeIds, tripToRoute, tripToService, tripToHeadsign) = try parseTrips(directory.appendingPathComponent("trips.txt"))
        let shapePoints = try parseShapes(directory.appendingPathComponent("shapes.txt"))
        let membership = try parseStopTimesForRouteMembership(
            directory.appendingPathComponent("stop_times.txt"),
            tripToRoute: tripToRoute,
            tripToHeadsign: tripToHeadsign
        )
        let activeServiceIdsByDate = try parseCalendarDates(directory.appendingPathComponent("calendar_dates.txt"))

        var shapes: [AtacLineShape] = []
        shapes.reserveCapacity(shapePoints.count)
        for (routeId, shapeIds) in routeToShapeIds {
            for shapeId in shapeIds {
                guard let points = shapePoints[shapeId], points.count > 1 else { continue }
                shapes.append(AtacLineShape(shapeId: shapeId, routeId: routeId, coordinates: points))
            }
        }

        return ParsedStatic(
            stops: stops,
            routes: routes,
            routeToShapeIds: routeToShapeIds,
            shapes: shapes,
            stopToRouteIds: membership.stopToRouteIds,
            tripToRoute: tripToRoute,
            tripToService: tripToService,
            tripToHeadsign: tripToHeadsign,
            stopHeadsignByRoute: membership.stopHeadsignByRoute,
            activeServiceIdsByDate: activeServiceIdsByDate
        )
    }

    /// Cleans a raw `trip_headsign` like "ANAGNINA (MA)" down to "Anagnina"
    /// — the "(MA)"/"(MB1)"/etc suffix is this feed's own internal line
    /// code, not meaningful to a rider, stripped the same way a GTFS stop
    /// name's own parenthetical suffix already is elsewhere
    /// (`GTFSTextUtils.extractLocalityFromStopName`). Headsigns in this feed
    /// are all-caps; `.capitalized` reads more like the rest of the app's UI.
    private static func cleanHeadsign(_ raw: String) -> String? {
        let cleaned = GTFSTextUtils.extractLocalityFromStopName(raw).capitalized
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func parseStops(_ url: URL) throws -> [AtacStop] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var stops: [AtacStop] = []
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = GTFSParsing.parseCSVLine(trimmed)
            guard fields.count > 5, let lat = Double(fields[4]), let lon = Double(fields[5]) else { return }
            stops.append(AtacStop(stopId: fields[0], stopName: fields[2], lat: lat, lon: lon))
        }
        return stops
    }

    private static func parseRoutes(_ url: URL) throws -> [String: AtacRoute] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var routes: [String: AtacRoute] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = GTFSParsing.parseCSVLine(trimmed)
            guard fields.count > 6 else { return }
            let routeType = Int(fields[4]) ?? 3
            let colorHex = fields[6].trimmingCharacters(in: .whitespaces)
            // Only agency_id "OP1" is Atac itself; every other agency in
            // this combined feed (TROIANI, TUSCIA, BIS, ATR Mobility) is a
            // constituent operator of the Roma TPL consortium — verified
            // against the feed's own agency.txt, which has no literal
            // "Roma TPL" agency entry.
            let transitOperator: TransitOperator = fields[1] == "OP1" ? .atac : .romaTpl
            routes[fields[0]] = AtacRoute(
                routeId: fields[0],
                routeShortName: fields[2],
                routeLongName: fields[3],
                kind: TransitVehicleKind(gtfsRouteType: routeType),
                transitOperator: transitOperator,
                colorHex: colorHex.isEmpty ? nil : colorHex
            )
        }
        return routes
    }

    /// route_id -> distinct shape_ids used by its trips, trip_id -> route_id
    /// (needed to resolve `stop_times.txt` rows to a route), trip_id ->
    /// service_id (needed to later filter a trip's departures by which
    /// calendar days it actually runs), and trip_id -> cleaned headsign
    /// (field index 3, e.g. "ANAGNINA (MA)" -> "Anagnina" — the destination
    /// a rider sees on the vehicle itself). Uses the quote-aware parser
    /// (trip_headsign can contain arbitrary quoted text, so a naive comma
    /// split would misalign the later shape_id column).
    private static func parseTrips(_ url: URL) throws -> (routeToShapeIds: [String: Set<String>], tripToRoute: [String: String], tripToService: [String: String], tripToHeadsign: [String: String]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        var routeToShapeIds: [String: Set<String>] = [:]
        var tripToRoute: [String: String] = [:]
        var tripToService: [String: String] = [:]
        var tripToHeadsign: [String: String] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let fields = GTFSParsing.parseCSVLine(trimmed)
            guard fields.count > 7 else { return }
            let routeId = fields[0]
            let serviceId = fields[1]
            let tripId = fields[2]
            let headsign = fields[3]
            let shapeId = fields[7]
            guard !routeId.isEmpty else { return }
            if !tripId.isEmpty {
                tripToRoute[tripId] = routeId
                if !serviceId.isEmpty { tripToService[tripId] = serviceId }
                if let cleaned = cleanHeadsign(headsign) { tripToHeadsign[tripId] = cleaned }
            }
            guard !shapeId.isEmpty else { return }
            routeToShapeIds[routeId, default: []].insert(shapeId)
        }
        return (routeToShapeIds, tripToRoute, tripToService, tripToHeadsign)
    }

    struct RouteMembership {
        var stopToRouteIds: [String: Set<String>]
        /// "routeId|stopId" -> that route's headsign at that stop — see
        /// `ParsedStatic.stopHeadsignByRoute`.
        var stopHeadsignByRoute: [String: String]
    }

    /// stop_id -> distinct route_ids serving it, resolved from
    /// `stop_times.txt` via `tripToRoute` — plus, piggy-backing on the same
    /// full pass since it already has both ids in hand for every row, each
    /// (route, stop) pair's headsign via `tripToHeadsign`. This file is huge
    /// (240MB, ~5.1M rows for the whole network) so — unlike everything else
    /// in this file — it's read as raw bytes and scanned by hand instead of
    /// going through `String.enumerateLines` (which does Unicode-correct
    /// grapheme scanning and is far too slow at this scale) or the
    /// quote-aware CSV parser. Only trip_id (column 0) and stop_id (column
    /// 3) are needed; neither is ever quoted in this feed in practice.
    private static func parseStopTimesForRouteMembership(_ url: URL, tripToRoute: [String: String], tripToHeadsign: [String: String]) throws -> RouteMembership {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var stopToRouteIds: [String: Set<String>] = [:]
        var stopHeadsignByRoute: [String: String] = [:]
        stopToRouteIds.reserveCapacity(10_000)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = raw.count
            let comma = UInt8(ascii: ",")
            let newline = UInt8(ascii: "\n")
            let carriageReturn = UInt8(ascii: "\r")

            func processLine(_ start: Int, _ end: Int) {
                var lineEnd = end
                if lineEnd > start, bytes[lineEnd - 1] == carriageReturn { lineEnd -= 1 }
                guard lineEnd > start else { return }

                var fieldStart = start
                var fieldIndex = 0
                var tripStart = start
                var tripEnd = start
                var j = start
                while j <= lineEnd {
                    if j == lineEnd || bytes[j] == comma {
                        if fieldIndex == 0 {
                            tripStart = fieldStart
                            tripEnd = j
                        } else if fieldIndex == 3 {
                            let tripId = String(decoding: UnsafeBufferPointer(start: bytes + tripStart, count: tripEnd - tripStart), as: UTF8.self)
                            guard let routeId = tripToRoute[tripId] else { return }
                            let stopId = String(decoding: UnsafeBufferPointer(start: bytes + fieldStart, count: j - fieldStart), as: UTF8.self)
                            stopToRouteIds[stopId, default: []].insert(routeId)
                            let key = "\(routeId)|\(stopId)"
                            if stopHeadsignByRoute[key] == nil, let headsign = tripToHeadsign[tripId] {
                                stopHeadsignByRoute[key] = headsign
                            }
                            return
                        }
                        fieldIndex += 1
                        fieldStart = j + 1
                    }
                    j += 1
                }
            }

            var lineStart = 0
            var isFirstLine = true
            var i = 0
            while i < count {
                if bytes[i] == newline {
                    if !isFirstLine { processLine(lineStart, i) }
                    isFirstLine = false
                    lineStart = i + 1
                }
                i += 1
            }
            if lineStart < count, !isFirstLine {
                processLine(lineStart, count)
            }
        }

        return RouteMembership(stopToRouteIds: stopToRouteIds, stopHeadsignByRoute: stopHeadsignByRoute)
    }

    /// shape_id -> ordered coordinates. Fast-path manual split (no
    /// quote-aware parsing) is safe here — every field is numeric — and
    /// matters at this file's scale (500k+ rows for the whole network).
    private static func parseShapes(_ url: URL) throws -> [String: [CLLocationCoordinate2D]] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var pointsBySequence: [String: [(Int, CLLocationCoordinate2D)]] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine || line.isEmpty { return }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 4,
                  let lat = Double(parts[1]), let lon = Double(parts[2]),
                  let sequence = Int(parts[3])
            else { return }
            let shapeId = String(parts[0])
            pointsBySequence[shapeId, default: []].append((sequence, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }

        var result: [String: [CLLocationCoordinate2D]] = [:]
        result.reserveCapacity(pointsBySequence.count)
        for (shapeId, points) in pointsBySequence {
            result[shapeId] = points.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return result
    }

    /// "yyyyMMdd" -> the service_ids that run that day. Tiny file (a few
    /// thousand rows for the whole network), plain `enumerateLines` is fine.
    private static func parseCalendarDates(_ url: URL) throws -> [String: Set<String>] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var byDate: [String: Set<String>] = [:]
        var isFirstLine = true
        content.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine || line.isEmpty { return }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3, fields[2] == "1" else { return }
            byDate[String(fields[1]), default: []].insert(String(fields[0]))
        }
        return byDate
    }

    struct ScheduledDeparture {
        let tripId: String
        let routeId: String
        let departureSeconds: Int
    }

    /// On-demand equivalent of `parseStopTimesForRouteMembership` above,
    /// scoped to a single stop instead of every stop in the network: same
    /// byte-level scan of the same cached `stop_times.txt` (still on disk
    /// from the original download/extraction), but matching stop_id
    /// (column 3) against one target and also pulling out departure_time
    /// (column 2) for matches, instead of building the whole-network
    /// membership map. Deliberately re-scans the file rather than reusing
    /// anything from the eager `parseAll` pass — see this file's header
    /// comment for why the full per-stop schedule isn't kept in memory.
    static func scheduledDepartures(forStopId targetStopId: String, in url: URL, tripToRoute: [String: String], activeServiceIds: Set<String>, tripToService: [String: String]) throws -> [ScheduledDeparture] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var results: [ScheduledDeparture] = []
        let targetBytes = Array(targetStopId.utf8)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = raw.count
            let comma = UInt8(ascii: ",")
            let newline = UInt8(ascii: "\n")
            let carriageReturn = UInt8(ascii: "\r")

            func processLine(_ start: Int, _ end: Int) {
                var lineEnd = end
                if lineEnd > start, bytes[lineEnd - 1] == carriageReturn { lineEnd -= 1 }
                guard lineEnd > start else { return }

                var fieldStart = start
                var fieldIndex = 0
                var tripStart = start
                var tripEnd = start
                var departureStart = start
                var departureEnd = start
                var j = start
                while j <= lineEnd {
                    if j == lineEnd || bytes[j] == comma {
                        switch fieldIndex {
                        case 0:
                            tripStart = fieldStart
                            tripEnd = j
                        case 2:
                            departureStart = fieldStart
                            departureEnd = j
                        case 3:
                            let fieldLength = j - fieldStart
                            guard fieldLength == targetBytes.count else { return }
                            var matches = true
                            for k in 0..<fieldLength where bytes[fieldStart + k] != targetBytes[k] {
                                matches = false
                                break
                            }
                            guard matches else { return }

                            let tripId = String(decoding: UnsafeBufferPointer(start: bytes + tripStart, count: tripEnd - tripStart), as: UTF8.self)
                            guard let routeId = tripToRoute[tripId],
                                  let serviceId = tripToService[tripId],
                                  activeServiceIds.contains(serviceId)
                            else { return }

                            let departureString = String(decoding: UnsafeBufferPointer(start: bytes + departureStart, count: departureEnd - departureStart), as: UTF8.self)
                            let parts = departureString.split(separator: ":")
                            guard parts.count == 3,
                                  let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2])
                            else { return }
                            results.append(ScheduledDeparture(tripId: tripId, routeId: routeId, departureSeconds: h * 3600 + m * 60 + s))
                            return
                        default:
                            break
                        }
                        fieldIndex += 1
                        fieldStart = j + 1
                    }
                    j += 1
                }
            }

            var lineStart = 0
            var isFirstLine = true
            var i = 0
            while i < count {
                if bytes[i] == newline {
                    if !isFirstLine { processLine(lineStart, i) }
                    isFirstLine = false
                    lineStart = i + 1
                }
                i += 1
            }
            if lineStart < count, !isFirstLine {
                processLine(lineStart, count)
            }
        }

        return results
    }
}
