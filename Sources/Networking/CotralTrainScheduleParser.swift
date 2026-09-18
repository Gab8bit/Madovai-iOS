import Foundation

/// Parses Cotral's train-schedule widget — an HTML fragment, not
/// structured data — into `CotralTrainStationSchedule`s. This is the most
/// fragile part of the whole feature: the markup comes from an
/// undocumented WordPress site with no public API contract, so it can
/// change without notice. Parsing is deliberately regex-based rather than
/// a full HTML/DOM parse: it only looks for the two class names that
/// actually carry the data (`LocalityAccordion__text heading-h3` for a
/// station name, `TimeCard__time`/`TimeCard__info` for a passage), and
/// ignores everything else about the surrounding markup. If the site's
/// styling framework changes but keeps these class names, parsing keeps
/// working; if the class names themselves change, this returns an empty
/// array rather than throwing — a schedule silently not loading is a far
/// better failure mode here than a crash on unexpected markup.
enum CotralTrainScheduleParser {
    /// - Parameter html: the widget's HTML, already unwrapped from
    ///   whatever envelope the endpoint sent it in (see
    ///   `CotralTrainScheduleEnvelope`).
    /// - Returns: one entry per station, in the order the source lists
    ///   them (the line's own stop order), each with its passages in
    ///   source order (already time-ascending in practice).
    static func parse(html: String) -> [CotralTrainStationSchedule] {
        let headers = matches(of: headerPattern, in: html, group: 1)
        guard !headers.isEmpty else { return [] }

        let times = matches(of: timePattern, in: html, group: 1)
        let statuses = matches(of: infoPattern, in: html, group: 1)
        // Every real sample had one status per time, in the same order
        // (each lives inside the same `TimeCard` div, time first) — if a
        // future markup change breaks that pairing, degrade to whichever
        // is shorter rather than crash on an out-of-bounds index.
        let passageCount = min(times.count, statuses.count)

        var stationOrder: [String] = []
        var passagesByStation: [String: [CotralTrainPassage]] = [:]
        for header in headers where passagesByStation[header.text] == nil {
            stationOrder.append(header.text)
            passagesByStation[header.text] = []
        }

        var headerIndex = 0
        for i in 0..<passageCount {
            let position = times[i].location
            while headerIndex + 1 < headers.count, headers[headerIndex + 1].location <= position {
                headerIndex += 1
            }
            guard headers[headerIndex].location <= position else { continue }
            let stationName = headers[headerIndex].text
            let passage = CotralTrainPassage(time: times[i].text, status: statuses[i].text)
            passagesByStation[stationName, default: []].append(passage)
        }

        return stationOrder.map { name in
            CotralTrainStationSchedule(stationName: name, passages: passagesByStation[name] ?? [])
        }
    }

    private static let headerPattern = #"LocalityAccordion__text heading-h3[^"]*">\s*<span>\s*([^<]+?)\s*</span>"#
    private static let timePattern = #"TimeCard__time[^"]*">\s*(\d{1,2}:\d{2})"#
    private static let infoPattern = #"TimeCard__info[^"]*">\s*([^<]+?)\s*</div>"#

    private struct Match {
        let location: Int
        let text: String
    }

    private static func matches(of pattern: String, in html: String, group: Int) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: group), in: html) else { return nil }
            return Match(location: match.range.location, text: String(html[range]))
        }
    }
}

/// Unwraps the HTML payload from `get-train-stopsroute`'s response body.
/// Handles three shapes actually observed from the live endpoint (this
/// WordPress backend is inconsistent between otherwise-identical calls,
/// confirmed empirically, not just a theoretical concern):
///
/// 1. Well-formed JSON: `{"status":200,"response":"<HTML, JSON-escaped>"}`.
/// 2. Malformed JSON with literal, unescaped control characters (real
///    newlines/tabs) inside the `"response"` string — breaks a strict
///    JSON parser even though the overall `{"response":"..."}` shape is
///    the same, so it needs a lenient manual unwrap instead.
/// 3. No JSON envelope at all: the raw HTML body directly, seen once
///    during testing on an otherwise-identical repeated request.
enum CotralTrainScheduleEnvelope {
    static func extractHTML(from body: String) -> String {
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            return body
        }

        if let data = body.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Envelope.self, from: data) {
            return decoded.response
        }

        return lenientUnwrap(body) ?? body
    }

    private struct Envelope: Decodable {
        let response: String
    }

    /// Finds `"response":"..."` by hand and undoes the handful of JSON
    /// string escapes this endpoint actually uses (`\"`, `\\`, `\/`, plus
    /// the standard whitespace escapes) with a single left-to-right scan —
    /// not chained `replacingOccurrences` calls, which can mis-unescape a
    /// sequence like `\\/` (an escaped backslash followed by a literal
    /// slash) if applied in the wrong order.
    private static func lenientUnwrap(_ body: String) -> String? {
        guard let startRange = body.range(of: "\"response\":\"") else { return nil }
        var content = String(body[startRange.upperBound...])
        if content.hasSuffix("\"}") {
            content.removeLast(2)
        } else if let lastQuote = content.range(of: "\"", options: .backwards) {
            content = String(content[..<lastQuote.lowerBound])
        }
        return unescape(content)
    }

    private static func unescape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var iterator = s.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\", let next = iterator.next() else {
                result.append(ch)
                continue
            }
            switch next {
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "/": result.append("/")
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            default:
                result.append(ch)
                result.append(next)
            }
        }
        return result
    }
}
