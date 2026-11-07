import Foundation

/// Debounced backend search ("contains", case-insensitive, both networks).
/// Used by the map search bar and by the reminder form (which filters out
/// metro stations, that have no per-stop live data).
@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    @Published private(set) var stops: [SearchStop] = []
    @Published private(set) var routes: [RouteInfo] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    /// How many stops `stopFilter` removed from the last result.
    @Published private(set) var filteredOutCount = 0

    private let api: MadovaiAPI
    private let includeRoutes: Bool
    private let stopFilter: ((SearchStop) -> Bool)?
    private var task: Task<Void, Never>?

    init(api: MadovaiAPI = .shared, includeRoutes: Bool = true, stopFilter: ((SearchStop) -> Bool)? = nil) {
        self.api = api
        self.includeRoutes = includeRoutes
        self.stopFilter = stopFilter
    }

    var hasResults: Bool { !stops.isEmpty || !routes.isEmpty }
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    func clear() {
        task?.cancel()
        query = ""
        stops = []
        routes = []
        isSearching = false
        errorMessage = nil
        filteredOutCount = 0
    }

    func retry() { schedule(debounce: 0) }

    private func schedule(debounce: TimeInterval = 0.25) {
        task?.cancel()
        let q = trimmedQuery
        guard !q.isEmpty else {
            stops = []
            routes = []
            isSearching = false
            errorMessage = nil
            filteredOutCount = 0
            return
        }
        task = Task { [weak self] in
            if debounce > 0 { try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            isSearching = true
            do {
                let response = try await api.search(q)
                guard !Task.isCancelled else { return }
                let usable = stopFilter.map { filter in response.stops.filter(filter) } ?? response.stops
                filteredOutCount = response.stops.count - usable.count
                stops = usable
                routes = includeRoutes ? response.routes : []
                errorMessage = nil
                isSearching = false
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                stops = []
                routes = []
                errorMessage = error.userMessage
                isSearching = false
            }
        }
    }
}

/// The "Linee" list is the same for everyone (~440 rows): loaded once and
/// shared by the Linee tab and the map's line focus.
@MainActor
final class LinesStore: ObservableObject {
    @Published private(set) var lines: LinesResponse?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let api: MadovaiAPI
    private var loadTask: Task<Result<LinesResponse, Error>, Never>?

    init(api: MadovaiAPI = .shared) {
        self.api = api
    }

    @discardableResult
    func load() async -> LinesResponse? {
        if let lines { return lines }
        let task: Task<Result<LinesResponse, Error>, Never>
        if let loadTask {
            task = loadTask
        } else {
            isLoading = true
            task = Task { [api] in
                do { return .success(try await api.lines()) } catch { return .failure(error) }
            }
            loadTask = task
        }
        let result = await task.value
        loadTask = nil
        isLoading = false
        switch result {
        case .success(let response):
            lines = response
            errorMessage = nil
            return response
        case .failure(let error):
            errorMessage = error.userMessage
            return nil
        }
    }

    func retry() {
        errorMessage = nil
        Task { await load() }
    }
}
