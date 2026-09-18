import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case network(String)
    case http(status: Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL non valido."
        case .network:
            return "Impossibile contattare Cotral. Controlla la connessione."
        case .http(let status):
            return "Cotral ha risposto con un errore (\(status))."
        case .noData:
            return "Nessun dato disponibile al momento."
        }
    }
}
