import UIKit

/// Runs an async action now and then every `interval`, but only while the
/// app is in the foreground (a backgrounded app shouldn't hammer the backend
/// or the battery), refreshing immediately when it comes back. Overlapping
/// runs are impossible: the next wait starts after the action returns.
@MainActor
final class Poller {
    private let interval: TimeInterval
    private let action: @MainActor () async -> Void
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isRunningAction = false

    init(interval: TimeInterval, action: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.action = action
    }

    var isActive: Bool { loop != nil }

    func start() {
        guard loop == nil else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshNow() }
            },
        ]
        startLoop()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Runs the action right away and restarts the interval from there —
    /// e.g. when the app becomes active or the connection comes back.
    ///
    /// Never cancels a run already in flight: cancelling the loop task also
    /// cancelled its network request, and at launch (where "did become
    /// active" arrives right after the first poll starts) that threw away
    /// the very first vehicle fetch and left the map empty for an interval.
    /// A refresh requested mid-run is queued and runs as soon as it ends.
    func refreshNow() {
        guard loop != nil else { return }
        if isRunningAction {
            refreshQueued = true
            return
        }
        loop?.cancel()
        startLoop()
    }

    private var refreshQueued = false

    private func startLoop() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ran = await self.tick()
                if self.refreshQueued {
                    self.refreshQueued = false
                    continue
                }
                // A skipped tick (app reported as background — which also
                // happens for a moment during launch) retries after a second
                // instead of losing a whole interval.
                let wait = ran ? self.interval : 1
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func tick() async -> Bool {
        guard UIApplication.shared.applicationState != .background else { return false }
        isRunningAction = true
        defer { isRunningAction = false }
        await action()
        return true
    }

    deinit {
        loop?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
