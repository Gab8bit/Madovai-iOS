import BackgroundTasks
import Foundation

/// Owns the app's single background wake-up chain for Promemoria.
///
/// Why local and not server push like the web app: the backend can send
/// APNs, but that needs a paid Apple Developer account, which a sideloaded
/// build doesn't have. So the phone itself wakes up (`BGAppRefreshTask`),
/// asks the backend for the next departure and posts a local notification.
///
/// `BGTaskScheduler` allows **one pending request per identifier** and the
/// permitted identifiers are a fixed Info.plist list, so there is exactly
/// one identifier, always pointed at whichever reminder (or retry) is
/// soonest. Every change to `ReminderStore` and the end of every background
/// run recompute it.
///
/// Limits (also stated in the form): iOS decides when the task really runs
/// (not to the minute, more reliable the more the app is used), and
/// force-quitting the app stops background tasks until it's opened again.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    static let taskIdentifier = "dev.gab8bit.madovai.reminderCheck"

    private static let pendingReminderIdKey = "dev.gab8bit.madovai.reminderPendingId"
    private static let retryCountKeyPrefix = "dev.gab8bit.madovai.reminderRetryCount."
    static let maxRetryAttempts = 15
    static let retryInterval: TimeInterval = 120

    private let defaults: UserDefaults
    private let notifier: ReminderNotifier
    private let fetcher: ReminderStatusFetcher
    /// `BGTaskScheduler.submit` for an identifier that was never registered
    /// is an uncaught NSException (a crash, not a Swift error). This happened
    /// in 1.3.0 when `ReminderStore.shared` was built before registration:
    /// nothing may submit until `registerBackgroundTask()` has run.
    private var isRegistered = false

    init(defaults: UserDefaults = .standard, notifier: ReminderNotifier = .shared, fetcher: ReminderStatusFetcher = ReminderStatusFetcher()) {
        self.defaults = defaults
        self.notifier = notifier
        self.fetcher = fetcher
    }

    /// Called from `CotralLiveApp.init()`, before launch completes, and
    /// without touching `ReminderStore.shared` (see `isRegistered`).
    func registerBackgroundTask() {
        guard !isRegistered else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in self?.handle(bgTask) }
        }
        isRegistered = true
    }

    /// The next fire date (after `after`) for a reminder's weekdays + time,
    /// in Rome time (the hour the user picked is a Rome departure time).
    nonisolated static func nextFireDate(for reminder: Reminder, after: Date, calendar: Calendar = RomeTime.calendar) -> Date? {
        guard !reminder.weekdays.isEmpty else { return nil }
        var earliest: Date?
        for weekday in reminder.weekdays {
            var components = DateComponents()
            components.weekday = weekday.rawValue
            components.hour = reminder.hour
            components.minute = reminder.minute
            components.second = 0
            guard let candidate = calendar.nextDate(after: after, matching: components, matchingPolicy: .nextTime) else { continue }
            if earliest.map({ candidate < $0 }) ?? true { earliest = candidate }
        }
        return earliest
    }

    /// Points the single pending request at the soonest upcoming reminder.
    func rescheduleNext(reminders: [Reminder]) {
        guard isRegistered else { return }
        let now = Date()
        let next = reminders
            .compactMap { reminder -> (Reminder, Date)? in
                Self.nextFireDate(for: reminder, after: now).map { (reminder, $0) }
            }
            .min { $0.1 < $1.1 }

        guard let next else {
            cancelPending()
            return
        }
        submit(reminderId: next.0.id, fireDate: next.1)
    }

    private func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor [weak self] in
            await self?.run()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    private func run() async {
        let store = ReminderStore.shared
        guard let pendingIdString = defaults.string(forKey: Self.pendingReminderIdKey),
              let pendingId = UUID(uuidString: pendingIdString),
              let reminder = store.reminders.first(where: { $0.id == pendingId })
        else {
            rescheduleNext(reminders: store.reminders)
            return
        }

        let status = try? await fetcher.status(for: reminder)
        guard !Task.isCancelled, let status else {
            // Failure or nothing upcoming: no notification, retry in 2 min
            // up to 15 times, then move on to the next occurrence.
            let attempt = incrementRetryCount(for: reminder.id)
            if attempt < Self.maxRetryAttempts {
                submit(reminderId: reminder.id, fireDate: Date().addingTimeInterval(Self.retryInterval))
            } else {
                resetRetryCount(for: reminder.id)
                rescheduleNext(reminders: store.reminders)
            }
            return
        }

        notifier.notify(reminder: reminder, status: status)
        resetRetryCount(for: reminder.id)
        rescheduleNext(reminders: store.reminders)
    }

    private func submit(reminderId: UUID, fireDate: Date) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = fireDate
        do {
            try BGTaskScheduler.shared.submit(request)
            defaults.set(reminderId.uuidString, forKey: Self.pendingReminderIdKey)
        } catch {
            // E.g. Background App Refresh disabled, or the simulator: the
            // next launch (ReminderStore.init) tries again.
        }
    }

    private func cancelPending() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        defaults.removeObject(forKey: Self.pendingReminderIdKey)
    }

    private func incrementRetryCount(for id: UUID) -> Int {
        let key = Self.retryCountKeyPrefix + id.uuidString
        let next = defaults.integer(forKey: key) + 1
        defaults.set(next, forKey: key)
        return next
    }

    private func resetRetryCount(for id: UUID) {
        defaults.removeObject(forKey: Self.retryCountKeyPrefix + id.uuidString)
    }
}
