import BackgroundTasks
import Foundation

/// Owns the app's single background wake-up chain for Promemoria.
///
/// `BGTaskScheduler` only allows **one pending request per task identifier**,
/// and `BGTaskSchedulerPermittedIdentifiers` in Info.plist is a fixed, static
/// list — it can't grow at runtime as the user creates more reminders. So
/// "each reminder independently schedules its own wake-up" isn't literally
/// possible; instead there is exactly one identifier
/// (`Self.taskIdentifier`), always pointed at whichever reminder (or retry
/// attempt) is chronologically soonest. Every mutation to `ReminderStore`,
/// and the end of every background run (success, retry, or give-up), calls
/// `rescheduleNext(reminders:)` to recompute and resubmit that one request.
///
/// Two real iOS limitations that follow from this, beyond the "not exact to
/// the minute" one already surfaced in `ReminderFormView`:
/// - Force-quitting the app from the app switcher stops iOS from running
///   its background tasks at all until the user manually reopens it once —
///   standard behavior for every app, not specific to this one.
/// - Only one reminder's wake-up is ever actually "in flight"; the chain
///   above keeps the *next* one queued automatically, but reliability of
///   the whole chain still depends on iOS actually running the shared task
///   promptly, which is itself best-effort and usage-pattern-dependent.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    static let taskIdentifier = "dev.gab8bit.madovai.reminderCheck"

    private static let pendingReminderIdKey = "dev.gab8bit.madovai.reminderPendingId"
    private static let retryCountKeyPrefix = "dev.gab8bit.madovai.reminderRetryCount."
    private static let maxRetryAttempts = 15
    private static let retryInterval: TimeInterval = 120

    private let defaults: UserDefaults
    private let notifier: ReminderNotifier
    /// Guards `submit`/`rescheduleNext` against ever running before
    /// `registerBackgroundTask()` has actually completed — `BGTaskScheduler`
    /// hard-aborts (an uncaught `NSException`, not a catchable Swift error)
    /// on `submit` for an identifier it was never told about via `register`.
    /// This was hit for real: `ReminderStore.shared`'s own `init()` calls
    /// `rescheduleNext` as a side effect of being constructed, and passing
    /// `.shared` as an *argument* to `registerBackgroundTask(reminderStore:)`
    /// (the original design) evaluates that argument — constructing the
    /// singleton and firing its reschedule — *before* the function body
    /// (which calls `register`) ever runs. Fixed by not taking a
    /// `reminderStore` parameter at all (this reads `ReminderStore.shared`
    /// directly, only from inside the launch handler, which by definition
    /// never fires until long after app launch/registration completes).
    private var isRegistered = false

    init(defaults: UserDefaults = .standard, notifier: ReminderNotifier = .shared) {
        self.defaults = defaults
        self.notifier = notifier
    }

    /// Must be called before the app finishes launching (from
    /// `CotralLiveApp.init()`), per `BGTaskScheduler`'s own requirement —
    /// and, deliberately, without touching `ReminderStore.shared` (see
    /// `isRegistered`'s doc comment above).
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(bgTask)
        }
        isRegistered = true
    }

    /// The next `Date` (from `after`) at which `reminder` should fire, given
    /// its weekdays+time — nil only when `weekdays` is empty. Pure and
    /// testable: standard `Calendar.nextDate(after:matching:)` idiom, looped
    /// over each selected weekday, taking the earliest result.
    nonisolated static func nextFireDate(for reminder: Reminder, after: Date, calendar: Calendar = .current) -> Date? {
        guard !reminder.weekdays.isEmpty else { return nil }
        var earliest: Date?
        for weekday in reminder.weekdays {
            var components = DateComponents()
            components.weekday = weekday.rawValue
            components.hour = reminder.hour
            components.minute = reminder.minute
            components.second = 0
            guard let candidate = calendar.nextDate(after: after, matching: components, matchingPolicy: .nextTime) else { continue }
            if earliest == nil || candidate < earliest! { earliest = candidate }
        }
        return earliest
    }

    /// Recomputes the single soonest upcoming trigger across every reminder
    /// and submits exactly one `BGAppRefreshTaskRequest` for it, replacing
    /// whatever was previously pending. Called after any reminder
    /// create/edit/delete, and at the end of every background run that
    /// isn't itself an in-progress retry (see `scheduleRetry`).
    func rescheduleNext(reminders: [Reminder]) {
        guard isRegistered else { return }
        let now = Date()
        let next = reminders
            .compactMap { reminder -> (Reminder, Date)? in
                guard let date = Self.nextFireDate(for: reminder, after: now) else { return nil }
                return (reminder, date)
            }
            .min { $0.1 < $1.1 }

        guard let next else {
            cancelPending()
            return
        }
        submit(reminderId: next.0.id, fireDate: next.1)
    }

    private func handle(_ task: BGAppRefreshTask) {
        let workTask = Task { @MainActor [weak self] in
            await self?.run(task: task)
        }
        task.expirationHandler = {
            workTask.cancel()
        }
    }

    private func run(task: BGAppRefreshTask) async {
        defer { task.setTaskCompleted(success: true) }

        let reminderStore = ReminderStore.shared
        guard let pendingIdString = defaults.string(forKey: Self.pendingReminderIdKey),
              let pendingId = UUID(uuidString: pendingIdString),
              let reminder = reminderStore.reminders.first(where: { $0.id == pendingId })
        else {
            rescheduleNext(reminders: reminderStore.reminders)
            return
        }

        guard !Task.isCancelled, let status = try? await fetchStatus(for: reminder) else {
            let attempt = incrementRetryCount(for: reminder.id)
            if attempt < Self.maxRetryAttempts {
                submit(reminderId: reminder.id, fireDate: Date().addingTimeInterval(Self.retryInterval))
            } else {
                resetRetryCount(for: reminder.id)
                rescheduleNext(reminders: reminderStore.reminders)
            }
            return
        }

        notifier.notify(reminder: reminder, status: status)
        resetRetryCount(for: reminder.id)
        rescheduleNext(reminders: reminderStore.reminders)
    }

    /// None of these repositories need the app's heavy GTFS stores — see
    /// `AtacStopArrivalClient`'s doc comment for why that matters inside a
    /// background task's short execution window.
    private func fetchStatus(for reminder: Reminder) async throws -> ReminderDepartureStatus? {
        switch reminder.source {
        case .cotralBus(let poleCode):
            guard let result = try await TransitsRepository().transits(poleCode: poleCode) else { return nil }
            return ReminderDepartureStatus.nextUpcoming(from: result.transits)
        case .cotralTrain(let stationName, let route):
            guard let direction = try await AstralTrainRepository().departures(for: route, stationName: stationName) else { return nil }
            return ReminderDepartureStatus.nextUpcoming(from: direction.entries.upcoming())
        case .atacStop(let stopId):
            let arrivals = try await AtacStopArrivalClient.shared.upcomingArrivals(stopId: stopId)
            return ReminderDepartureStatus.nextUpcoming(from: arrivals)
        }
    }

    private func submit(reminderId: UUID, fireDate: Date) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = fireDate
        do {
            try BGTaskScheduler.shared.submit(request)
            defaults.set(reminderId.uuidString, forKey: Self.pendingReminderIdKey)
        } catch {
            // Submission can fail (e.g. too many requests system-wide, or
            // running in an environment without background refresh) — there
            // is no user-facing surface for this today; the reminder simply
            // won't fire until the next successful reschedule (e.g. the app
            // being opened again re-triggers `ReminderStore.init`'s own
            // `rescheduleNext` call).
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
