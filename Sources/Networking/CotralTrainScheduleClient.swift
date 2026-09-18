import Foundation

/// Talks to Cotral's train-schedule widget endpoint
/// (`cotralspa.it/wp-json/cotral/v1/get-train-stopsroute`) — a completely
/// separate, unrelated backend from `CotralXMLClient`'s PIV.do/Automezzi.do
/// (different host, different protocol: JSON-wrapped HTML instead of XML)
/// and from the GTFS static feeds. Public, no auth, no shared client id.
/// See `CotralTrainStationSchedule`'s doc comment for why this data is a
/// published timetable with a generic status tag, not per-train tracking,
/// despite the URL/markup both calling it "realtime".
actor CotralTrainScheduleClient {
    static let shared = CotralTrainScheduleClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Config.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    /// - Parameters:
    ///   - route: which line + direction (`codicePercorso`).
    ///   - date: defaults to now; only the day matters, converted to the
    ///     `DDMMYYYY` format the endpoint expects.
    /// - Returns: one entry per station on that route for that day, or an
    ///   empty array if Cotral has nothing (an invalid code or a malformed
    ///   date both come back as an empty-but-200 response in practice,
    ///   verified with `curl` — not an error condition worth throwing for).
    func fetchSchedule(for route: CotralTrainRoute, date: Date = Date()) async throws -> [CotralTrainStationSchedule] {
        guard var components = URLComponents(url: Config.cotralTrainScheduleBaseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "codicePercorso", value: route.rawValue),
            URLQueryItem(name: "date", value: Self.dateString(for: date)),
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw APIError.http(status: httpResponse.statusCode)
        }

        guard let body = String(data: data, encoding: .utf8) else { return [] }
        let html = CotralTrainScheduleEnvelope.extractHTML(from: body)
        return CotralTrainScheduleParser.parse(html: html)
    }

    /// `DDMMYYYY` — verified against the real endpoint with `curl`; today's
    /// date in this format returns real data, and Rome's own timezone is
    /// used since "today" should mean Rome's today, not the device's.
    private static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyy"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        return formatter.string(from: date)
    }
}
