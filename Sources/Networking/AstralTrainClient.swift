import Foundation

/// Talks to ASTRAL's live-schedule API (`gestionecorse.astralspa.it`) — a
/// completely separate, unrelated backend from Cotral's own `PIV.do`
/// (`CotralXMLClient`) or the retired cotralspa.it widget. Public, no auth,
/// plain JSON in and out (confirmed reachable with a bare POST + JSON body,
/// no special headers/referer needed — unlike the `/api/monitoraggio/...`
/// endpoints, which return "DIVIETO DI ACCESSO" to a plain call and aren't
/// used by this app).
actor AstralTrainClient {
    static let shared = AstralTrainClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Config.requestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    /// `POST /api/fermate/<percorso>` — the full ordered station list for
    /// one line+direction (name, ASTRAL's own stop code, sequence).
    func fetchStations(percorso: String) async throws -> [AstralStation] {
        try await post(path: "fermate/\(percorso)", body: [:])
    }

    /// `POST /api/transit` — one station's entire day of passages for a
    /// line+direction (time, delay, cancelled, replacement-bus).
    func fetchTransits(percorso: String, fermata: String) async throws -> [AstralTransitDTO] {
        try await post(path: "transit", body: ["percorso": percorso, "fermata": fermata])
    }

    private func post<T: Decodable>(path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: Config.astralBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(status: http.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Raw shape of one `/api/transit` entry — `ritardo`/`soppressa`/
/// `busSostitutivo` arrive as strings (an empty `ritardo` means "not yet
/// computed", not zero), converted to proper types by `AstralTrainRepository`.
struct AstralTransitDTO: Decodable {
    let orario: String
    let corsa: String
    let ritardo: String
    let soppressa: String
    let busSostitutivo: String
}
