import UserNotifications

/// Posts the local notification a Promemoria's background check produces.
/// Authorization is requested contextually (the first time the user saves a
/// reminder), not eagerly at launch, so people who never touch this feature
/// are never prompted.
@MainActor
final class ReminderNotifier {
    static let shared = ReminderNotifier()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notify(reminder: Reminder, status: ReminderDepartureStatus) {
        let vehicleWord = reminder.source.isTrain ? "treno" : "bus"
        let content = UNMutableNotificationContent()
        content.title = "Prossimo \(vehicleWord) alle \(status.time)"
        content.body = bodyText(reminder: reminder, status: status, vehicleWord: vehicleWord)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    private func bodyText(reminder: Reminder, status: ReminderDepartureStatus, vehicleWord: String) -> String {
        var target = "per \(reminder.stopName)"
        if case .cotralTrain(_, let route) = reminder.source {
            target += ", direzione \(route.directionLabel)"
        }

        if status.isCancelled {
            let fallback = status.nextUsefulTime.map { " Prossimo utile: \($0)." } ?? " Nessun'altra corsa in programma."
            return "Il prossimo \(vehicleWord) \(target) è stato soppresso.\(fallback)"
        }
        guard let delayMinutes = status.delayMinutes, delayMinutes >= 1 else {
            return "Il prossimo \(vehicleWord) \(target) non fa ritardo."
        }
        return "Il prossimo \(vehicleWord) \(target) è in ritardo di \(delayMinutes) minut\(delayMinutes == 1 ? "o" : "i")."
    }
}
