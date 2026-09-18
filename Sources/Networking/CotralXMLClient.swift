import Foundation

/// Talks directly to Cotral's own internal live-data endpoint (the same one
/// `packages/server` in ChromuSx/cotral proxies) and parses its XML
/// responses. No middleman server — this IS the client.
actor CotralXMLClient {
    static let shared = CotralXMLClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // `.ephemeral`, not `.default`: every poll re-requests the exact
            // same URL (same pole code, no cache-busting param), and
            // `.default` backs onto the shared `URLCache`. If Cotral's
            // legacy servlet endpoint ever sends caching headers (even by
            // accident), `.default` can silently serve a stale response
            // instead of hitting the network — which looked exactly like a
            // "stuck" delay value that never updates while polling
            // continues. `GTFSStore`/`AtacGtfsStore` already use `.ephemeral`
            // for the same reason.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Config.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    /// - Parameters:
    ///   - endpoint: e.g. "PIV.do" or "Automezzi.do".
    ///   - params: query parameters, matching the reference server's own
    ///     request shape for each `cmd`.
    /// - Returns: the parsed root XML node, or nil if Cotral had no data
    ///   for this query (a dangling closing tag / empty body).
    func fetchXML(endpoint: String, params: [String: String]) async throws -> XMLNode? {
        guard var components = URLComponents(url: Config.cotralBaseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
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

        return XMLNodeParser.parse(data)
    }
}
