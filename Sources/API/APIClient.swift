import Foundation

/// A failed backend call, with a message that can be shown to the user as is
/// (the backend's own errors are already in Italian: `{"error": "…"}`).
struct APIError: LocalizedError, Equatable {
    enum Kind: Equatable {
        /// No connection, DNS failure, host unreachable.
        case offline
        /// The request didn't complete within `Config.requestTimeout`.
        case timeout
        /// 503: the backend is still building its static data (or a push
        /// channel isn't configured).
        case notReady
        /// 429: more than 300 requests per minute from this IP.
        case rateLimited
        /// 400/404: missing parameter, unknown line/stop.
        case badRequest
        /// 502 and any other non-2xx status.
        case server(Int)
        /// The body wasn't the JSON we expected.
        case decoding
    }

    let kind: Kind
    let message: String

    var errorDescription: String? { message }

    /// Worth an automatic retry (as opposed to a request that will keep
    /// failing the same way, like an unknown stop id).
    var isTransient: Bool {
        switch kind {
        case .offline, .timeout, .notReady, .rateLimited, .server: return true
        case .badRequest, .decoding: return false
        }
    }

    static let offline = APIError(kind: .offline, message: "Connessione assente o server non raggiungibile.")
    static let timeout = APIError(kind: .timeout, message: "Il server non risponde. Riprova tra qualche secondo.")
    static let decoding = APIError(kind: .decoding, message: "Risposta del server non valida.")
}

/// Thin JSON-over-HTTP client for the Madovai backend. Stateless and safe to
/// share; every call runs off the main actor (decoding included), so views
/// only ever receive ready-made values.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL = Config.apiBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Config.requestTimeout
            configuration.timeoutIntervalForResource = Config.requestTimeout * 2
            configuration.waitsForConnectivity = false
            // Every response carries `Cache-Control: max-age` (3–10 s for
            // live data, up to 1 h for static data): honouring it avoids
            // re-downloading what can't have changed yet.
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0)
            configuration.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: configuration)
        }
    }

    /// `GET {baseURL}/{path}?{query}` decoded as `T`. Empty/nil query values
    /// are omitted; values are percent-encoded (Atac trip ids contain `#`).
    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        try await perform(URLRequest(url: url(path, query: query)), as: type)
    }

    /// For the few endpoints that live outside `/api/v1` (e.g. `/health`).
    func get<T: Decodable>(absolute url: URL, as type: T.Type = T.self) async throws -> T {
        try await perform(URLRequest(url: url), as: type)
    }

    func url(_ path: String, query: [String: String?] = [:]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query
            .compactMap { key, value -> URLQueryItem? in
                guard let value, !value.isEmpty else { return nil }
                return URLQueryItem(name: key, value: value)
            }
            .sorted { $0.name < $1.name }
        if !items.isEmpty {
            components.queryItems = items
            // URLComponents leaves "#", "+" and "&" inside values ambiguous;
            // encode them explicitly (`encodeURIComponent` semantics).
            components.percentEncodedQuery = items
                .map { "\(Self.encode($0.name))=\(Self.encode($0.value ?? ""))" }
                .joined(separator: "&")
        }
        return components.url!
    }

    private static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~,")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? value
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.map(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, body: data)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    /// Transport errors → `APIError`; cancellation is passed through untouched
    /// so callers can tell "superseded by a newer request" from a failure.
    static func map(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let apiError = error as? APIError { return apiError }
        guard let urlError = error as? URLError else { return APIError.offline }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .timedOut:
            return APIError.timeout
        case .cannotParseResponse, .badServerResponse, .cannotDecodeContentData, .cannotDecodeRawData:
            return APIError.decoding
        default:
            return APIError.offline
        }
    }

    static func error(status: Int, body: Data) -> APIError {
        struct Body: Decodable { let error: String? }
        let serverMessage = (try? JSONDecoder().decode(Body.self, from: body))?.error
        switch status {
        case 503:
            return APIError(kind: .notReady, message: serverMessage ?? "Il server sta ancora preparando i dati. Riprova tra un minuto.")
        case 429:
            return APIError(kind: .rateLimited, message: serverMessage ?? "Troppe richieste. Riprova tra qualche secondo.")
        case 400, 404:
            return APIError(kind: .badRequest, message: serverMessage ?? "Richiesta non valida (\(status)).")
        case 502:
            return APIError(kind: .server(status), message: serverMessage ?? "La fonte dei dati non risponde. Riprova tra qualche secondo.")
        default:
            return APIError(kind: .server(status), message: serverMessage ?? "Errore del server (\(status)).")
        }
    }
}

extension Error {
    /// The text to show for any error coming out of the API layer.
    var userMessage: String {
        (self as? APIError)?.message ?? APIError.offline.message
    }

    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
