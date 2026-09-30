import SwiftUI

@main
struct CotralLiveApp: App {
    init() {
        // Must happen before the app finishes launching, per
        // `BGTaskScheduler`'s own requirement — this runs here rather than
        // in `ContentView.init()` (which isn't invoked until `body` below
        // is evaluated) specifically to guarantee that ordering. Crucially,
        // this must NOT touch `ReminderStore.shared` — see
        // `ReminderScheduler`'s doc comment for why doing so used to crash
        // every launch with a saved reminder.
        ReminderScheduler.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
