import SwiftUI

/// Create/edit a Promemoria. The stop is picked with the backend search;
/// metro stations are excluded (no per-stop live data in the feeds).
struct ReminderFormView: View {
    @ObservedObject var reminderStore: ReminderStore
    let editing: Reminder?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = SearchModel(includeRoutes: false, stopFilter: { !($0.source == "atac" && $0.metro) })

    @State private var stopName: String
    @State private var source: ReminderSource?
    @State private var trainDirections: [CotralTrainRoute]
    @State private var weekdays: Set<Weekday>
    @State private var time: Date
    @State private var isResolvingStation = false
    @State private var stationError: String?

    init(reminderStore: ReminderStore, editing: Reminder?) {
        self.reminderStore = reminderStore
        self.editing = editing
        _stopName = State(initialValue: editing?.stopName ?? "")
        _source = State(initialValue: editing?.source)
        _weekdays = State(initialValue: editing?.weekdays ?? [.monday, .tuesday, .wednesday, .thursday, .friday])
        if case .cotralTrain(_, let route, _) = editing?.source {
            _trainDirections = State(initialValue: CotralTrainRoute.directions(forGTFSRouteShortName: route.gtfsRouteShortName) ?? [route])
        } else {
            _trainDirections = State(initialValue: [])
        }
        var components = DateComponents()
        components.hour = editing?.hour ?? RomeTime.clock().hour
        components.minute = editing?.minute ?? RomeTime.clock().minute
        _time = State(initialValue: RomeTime.calendar.date(from: components) ?? Date())
    }

    private var canSave: Bool { source != nil && !weekdays.isEmpty && !isResolvingStation }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fermata") { stopSection }

                if trainDirections.count > 1, case .cotralTrain(let stationName, let currentRoute, let stopId) = source {
                    Section("Direzione") {
                        Picker("Direzione", selection: Binding(
                            get: { currentRoute },
                            set: { source = .cotralTrain(stationName: stationName, route: $0, stopId: stopId) }
                        )) {
                            ForEach(trainDirections) { Text($0.directionLabel).tag($0) }
                        }
                    }
                }

                Section("Giorni") { weekdayPicker }

                Section("Orario") {
                    DatePicker("Orario", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, RomeTime.timeZone)
                }

                Section {
                    Label(
                        "Riceverai una notifica con il prossimo passaggio e il suo stato (puntuale, in ritardo o soppresso). L'orario è approssimativo: iOS decide il momento esatto del controllo in background, che è più affidabile se usi spesso l'app.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let editing {
                    Section {
                        Button("Elimina promemoria", role: .destructive) {
                            reminderStore.delete(editing)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nuovo promemoria" : "Modifica promemoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva", action: save).disabled(!canSave) }
            }
        }
    }

    @ViewBuilder
    private var stopSection: some View {
        if source != nil || isResolvingStation {
            HStack {
                Text(stopName)
                Spacer()
                if isResolvingStation { ProgressView().controlSize(.small) }
                Button("Cambia") {
                    source = nil
                    stopName = ""
                    trainDirections = []
                    stationError = nil
                }
                .font(.caption)
            }
        } else {
            TextField("Cerca una fermata…", text: $search.query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if let stationError {
                Label(stationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            if search.isSearching {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Cerco…").font(.caption).foregroundStyle(.secondary) }
            }
            if let error = search.errorMessage {
                Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.red)
            }
            if search.filteredOutCount > 0 {
                Label("Dati in tempo reale non disponibili per la metro.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !search.trimmedQuery.isEmpty, !search.isSearching, search.errorMessage == nil, search.stops.isEmpty {
                Text("Nessuna fermata trovata.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(search.stops) { stop in
                Button { select(stop) } label: {
                    HStack {
                        Image(systemName: stop.iconName).foregroundStyle(.secondary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stop.name).foregroundStyle(.primary)
                            Text(stop.subtitle).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.mondayFirstOrder) { day in
                let isOn = weekdays.contains(day)
                Button {
                    if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(day.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(isOn ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func select(_ stop: SearchStop) {
        stopName = stop.name
        stationError = nil
        search.clear()
        if stop.isCotral && stop.rail {
            isResolvingStation = true
            Task {
                defer { isResolvingStation = false }
                do {
                    let pole = try await MadovaiAPI.shared.pole(id: stop.stopId)
                    let routes = (pole.trainRoutes ?? []).compactMap(CotralTrainRoute.init(rawValue:))
                    guard let first = routes.first else {
                        stationError = "Nessuna linea ferroviaria trovata per questa stazione."
                        stopName = ""
                        return
                    }
                    trainDirections = routes
                    source = .cotralTrain(stationName: stop.name, route: first, stopId: stop.stopId)
                } catch {
                    stationError = error.userMessage
                    stopName = ""
                }
            }
        } else if stop.isCotral {
            trainDirections = []
            source = .cotralBus(poleCode: stop.stopId)
        } else {
            trainDirections = []
            source = .atacStop(stopId: stop.stopId)
        }
    }

    private func save() {
        guard let source else { return }
        let components = RomeTime.calendar.dateComponents([.hour, .minute], from: time)
        let reminder = Reminder(
            id: editing?.id ?? UUID(),
            stopName: stopName,
            weekdays: weekdays,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            source: source
        )
        if editing != nil {
            reminderStore.update(reminder)
        } else {
            reminderStore.add(reminder)
        }
        Task { await ReminderNotifier.shared.requestAuthorizationIfNeeded() }
        dismiss()
    }
}
