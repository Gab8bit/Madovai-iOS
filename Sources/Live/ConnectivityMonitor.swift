import Foundation
import Network

/// Whether the phone is online and whether the backend is ready, for the
/// banners at the top of the map. Other services subscribe to
/// `onReconnect` to refresh right away instead of waiting a full interval.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    enum ServerState: Equatable {
        case unknown
        case ready
        /// `gtfsReady == false`: the server is (re)building its static data.
        case preparing
        /// Online but the backend can't be reached / answers with errors.
        case unreachable(String)
    }

    @Published private(set) var isOnline = true
    @Published private(set) var serverState: ServerState = .unknown

    private let pathMonitor = NWPathMonitor()
    private let api: MadovaiAPI
    private var reconnectHandlers: [@MainActor () -> Void] = []
    private var healthTask: Task<Void, Never>?
    private var started = false

    init(api: MadovaiAPI = .shared) {
        self.api = api
    }

    func start() {
        guard !started else { return }
        started = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "madovai.network-monitor"))
        checkServer()
    }

    func onReconnect(_ handler: @escaping @MainActor () -> Void) {
        reconnectHandlers.append(handler)
    }

    /// Called by data loaders after a successful request, so a stale
    /// "server unreachable" banner disappears without waiting for a probe.
    func reportSuccess() {
        if serverState != .ready, serverState != .preparing { serverState = .ready }
    }

    /// Called by data loaders on failure: a 503 means "preparing", anything
    /// else while online triggers a health probe to tell a global outage
    /// from a single failed endpoint.
    func report(_ error: Error) {
        guard let apiError = error as? APIError else { return }
        if apiError.kind == .notReady {
            serverState = .preparing
            scheduleHealthCheck(after: 20)
        } else if isOnline, apiError.kind == .offline || apiError.kind == .timeout {
            checkServer()
        }
    }

    func checkServer() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let health = try await api.health()
                guard !Task.isCancelled else { return }
                serverState = health.gtfsReady ? .ready : .preparing
                if !health.gtfsReady { scheduleHealthCheck(after: 20) }
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                serverState = isOnline ? .unreachable(error.userMessage) : .unknown
                if isOnline { scheduleHealthCheck(after: 30) }
            }
        }
    }

    private func scheduleHealthCheck(after seconds: TimeInterval) {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.checkServer()
        }
    }

    private func update(online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline {
            checkServer()
            reconnectHandlers.forEach { $0() }
        }
    }
}
