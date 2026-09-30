import SwiftUI

/// The "Promemoria" tab — same self-contained-tab shape as
/// `FavoritesListView`: its own `NavigationView`, a plain list, tap to edit.
struct RemindersListView: View {
    @ObservedObject var reminderStore: ReminderStore
    let gtfsStore: GTFSStore
    @ObservedObject var atacGtfsStore: AtacGtfsStore

    @State private var editingReminder: Reminder?
    @State private var isPresentingNewReminder = false

    var body: some View {
        NavigationView {
            Group {
                if reminderStore.reminders.isEmpty {
                    EmptyStateView(
                        systemImage: "bell",
                        title: "Nessun promemoria",
                        message: "Crea un promemoria per ricevere una notifica sul prossimo bus o treno all'orario che scegli."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(reminderStore.reminders) { reminder in
                            Button {
                                editingReminder = reminder
                            } label: {
                                ReminderRow(reminder: reminder)
                            }
                            .buttonStyle(.plain)
                            // `.onDelete`'s swipe action label is the
                            // system's own localized "Delete" string, which
                            // follows the device's language, not the app's
                            // (this app is all-Italian, no localization
                            // infrastructure) — an explicit action gives
                            // Italian text unconditionally.
                            .swipeActions(edge: .trailing) {
                                Button("Elimina", role: .destructive) {
                                    reminderStore.delete(reminder)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Promemoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingNewReminder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderFormView(reminderStore: reminderStore, gtfsStore: gtfsStore, atacGtfsStore: atacGtfsStore, editing: reminder)
        }
        .sheet(isPresented: $isPresentingNewReminder) {
            ReminderFormView(reminderStore: reminderStore, gtfsStore: gtfsStore, atacGtfsStore: atacGtfsStore, editing: nil)
        }
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
                Text(reminder.stopName)
                    .foregroundStyle(.primary)
                if case .cotralTrain(_, let route) = reminder.source {
                    Text(route.directionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
