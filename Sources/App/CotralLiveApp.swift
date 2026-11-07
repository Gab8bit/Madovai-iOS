import SwiftUI

@main
struct CotralLiveApp: App {
    private let env: AppEnvironment

    init() {
        // Must run before launch completes, and before anything touches
        // `ReminderStore.shared` (whose init reschedules the background
        // task: submitting before registering is a crash — see
        // `ReminderScheduler.isRegistered`). The environment, which builds
        // the reminder store, is therefore created right after.
        ReminderScheduler.shared.registerBackgroundTask()
        env = AppEnvironment()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(env: env)
        }
    }
}
