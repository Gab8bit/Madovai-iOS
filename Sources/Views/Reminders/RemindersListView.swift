import SwiftUI
import UserNotifications

/// The "Promemoria" tab: list, tap to edit, swipe to delete.
struct RemindersListView: View {
    @ObservedObject var reminderStore: ReminderStore

    @State private var editingReminder: Reminder?
    @State private var isPresentingNewReminder = false
    @State private var notificationsDenied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if reminderStore.reminders.isEmpty {
                    EmptyStateView(
                        systemImage: "bell",
                        title: "Nessun promemoria",
                        message: "Crea un promemoria per ricevere una notifica sul prossimo bus o treno all'orario che scegli.",
                        actionTitle: "Nuovo promemoria",
                        action: { isPresentingNewReminder = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if notificationsDenied {
                            Section {
                                Label {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Le notifiche sono disattivate per Madovai: i promemoria non potranno avvisarti.")
                                            .font(.footnote)
                                        Button("Apri Impostazioni") {
                                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                        }
                                        .font(.footnote.weight(.semibold))
                                    }
                                } icon: {
                                    Image(systemName: "bell.slash").foregroundStyle(.red)
                                }
                            }
                        }
                        Section {
                            ForEach(reminderStore.reminders) { reminder in
                                Button { editingReminder = reminder } label: { ReminderRow(reminder: reminder) }
                                    .buttonStyle(.plain)
                                    // Explicit label: `.onDelete` would show the
                                    // system's "Delete", in the device language.
                                    .swipeActions(edge: .trailing) {
                                        Button("Elimina", role: .destructive) { reminderStore.delete(reminder) }
                                    }
                            }
                        } footer: {
                            Text("Il controllo avviene sul telefono all'orario scelto: iOS decide il momento esatto, quindi può tardare di qualche minuto. Se chiudi l'app forzatamente dal multitasking, i promemoria si fermano finché non la riapri.")
                        }
                    }
                }
            }
            .navigationTitle("Promemoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isPresentingNewReminder = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Nuovo promemoria")
                }
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderFormView(reminderStore: reminderStore, editing: reminder)
        }
        .sheet(isPresented: $isPresentingNewReminder) {
            ReminderFormView(reminderStore: reminderStore, editing: nil)
        }
        .task(id: scenePhase) { await refreshPermission() }
        .onChange(of: isPresentingNewReminder) { _ in Task { await refreshPermission() } }
    }

    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }
}

private struct ReminderRow: View {
    let reminder: Reminder

    var body: some View {
        HStack {
            Image(systemName: reminder.source.isTrain ? "tram.fill" : "bus")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.stopName).foregroundStyle(.primary)
                if case .cotralTrain(_, let route, _) = reminder.source {
                    Text(route.directionLabel).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(reminder.weekdaysLabel) · \(reminder.timeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
