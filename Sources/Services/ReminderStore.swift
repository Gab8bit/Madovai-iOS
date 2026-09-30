import Foundation

/// Reminders, purely local (UserDefaults) — same persistence pattern as
/// `FavoritesStore`. Any mutation recomputes the app's single pending
/// background wake-up via `ReminderScheduler` (see that file's doc comment
/// for why there's only ever one, regardless of how many reminders exist).
@MainActor
final class ReminderStore: ObservableObject {
    /// A true singleton (unlike `FavoritesStore`/the GTFS stores, which
    /// `ContentView` owns itself) because `CotralLiveApp.init()` needs the
    /// exact same instance the UI observes to register the background task
    /// before the app finishes launching — before `ContentView` itself is
    /// ever constructed.
    static let shared = ReminderStore()

    @Published private(set) var reminders: [Reminder] = []

    private static let storageKey = "dev.gab8bit.madovai.reminders"
    private let defaults: UserDefaults
    private let scheduler: ReminderScheduler

    init(defaults: UserDefaults = .standard, scheduler: ReminderScheduler = .shared) {
        self.defaults = defaults
        self.scheduler = scheduler
        load()
        scheduler.rescheduleNext(reminders: reminders)
    }

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        persist()
    }

    func update(_ reminder: Reminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        persist()
    }

    func delete(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data)
        else { return }
        reminders = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: Self.storageKey)
        scheduler.rescheduleNext(reminders: reminders)
    }
}
