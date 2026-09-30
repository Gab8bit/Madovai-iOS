import SwiftUI

/// Create/edit a Promemoria. Reuses the app's existing search *logic* and
/// result types (`GTFSStore.searchStops`/`AtacGtfsStore.searchStops`,
/// `SearchStopResult`) rather than `StopLineSearchBar` itself, which is
/// coupled to `MapViewModel`'s map-camera side effects (`jumpTo`/
/// `centerOn`) that don't belong in a form.
struct ReminderFormView: View {
    @ObservedObject var reminderStore: ReminderStore
    let gtfsStore: GTFSStore
    @ObservedObject var atacGtfsStore: AtacGtfsStore
    let editing: Reminder?

    @Environment(\.dismiss) private var dismiss

    @State private var stopName: String
    @State private var source: ReminderSource?
    @State private var trainDirectionCandidates: [CotralTrainRoute]
    @State private var weekdays: Set<Weekday>
    @State private var time: Date
    @State private var searchText = ""
    @State private var searchResults: [SearchStopResult] = []
    @State private var metroExcludedFromSearch = false

    init(reminderStore: ReminderStore, gtfsStore: GTFSStore, atacGtfsStore: AtacGtfsStore, editing: Reminder?) {
        self.reminderStore = reminderStore
        self.gtfsStore = gtfsStore
        self.atacGtfsStore = atacGtfsStore
        self.editing = editing
        _stopName = State(initialValue: editing?.stopName ?? "")
        _source = State(initialValue: editing?.source)
        _weekdays = State(initialValue: editing?.weekdays ?? [])
        if case .cotralTrain(_, let route) = editing?.source {
            _trainDirectionCandidates = State(initialValue: CotralTrainRoute.directions(forGTFSRouteShortName: route.gtfsRouteShortName) ?? [route])
        } else {
            _trainDirectionCandidates = State(initialValue: [])
        }
        if let editing {
            var components = DateComponents()
            components.hour = editing.hour
            components.minute = editing.minute
            _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
        } else {
            _time = State(initialValue: Date())
        }
    }

    /// Every Atac `stop_id` belonging to a metro line — metro has no
    /// per-stop live data in either GTFS-RT feed (confirmed against the
    /// project's own README), so reminders can't target it.
    private var metroStopIds: Set<String> {
        Set(AtacMetroLine.allCases.flatMap { atacGtfsStore.stopsForRoute($0.rawValue) }.map(\.stopId))
    }

    private var canSave: Bool {
        source != nil && !weekdays.isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Fermata") {
                    if source != nil {
                        HStack {
                            Text(stopName)
                            Spacer()
                            Button("Cambia") { source = nil; stopName = ""; trainDirectionCandidates = [] }
                                .font(.caption)
                        }
                    } else {
                        TextField("Cerca una fermata…", text: $searchText)
                            .onChange(of: searchText, perform: search)
                        if metroExcludedFromSearch {
                            Label("Dati in tempo reale non disponibili per la metro.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(searchResults) { result in
                            Button {
                                select(result)
                            } label: {
                                HStack {
                                    Image(systemName: result.iconName).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.name).foregroundStyle(.primary)
                                        Text(result.subtitle).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if trainDirectionCandidates.count > 1, case .cotralTrain(let stationName, let currentRoute) = source {
                    Section("Direzione") {
                        Picker("Direzione", selection: Binding(
                            get: { currentRoute },
                            set: { source = .cotralTrain(stationName: stationName, route: $0) }
                        )) {
                            ForEach(trainDirectionCandidates) { route in
                                Text(route.directionLabel).tag(route)
                            }
                        }
                    }
                }

                Section("Giorni") {
                    weekdayPicker
                }

                Section("Orario") {
                    DatePicker("Orario", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                Section {
                    Label(
                        "L'orario di esecuzione è approssimativo, non garantito al minuto. L'affidabilità del risveglio in background dipende da quanto spesso apri l'app.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if editing != nil {
                    Section {
                        Button("Elimina promemoria", role: .destructive) {
                            if let editing { reminderStore.delete(editing) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nuovo promemoria" : "Modifica promemoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salva", action: save).disabled(!canSave)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.mondayFirstOrder) { day in
                Button {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(day.shortLabel)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(weekdays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(weekdays.contains(day) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            metroExcludedFromSearch = false
            return
        }
        let cotral = gtfsStore.searchStops(query: trimmed).map(SearchStopResult.cotral)
        let atacRaw = atacGtfsStore.searchStops(query: trimmed)
        let metroIds = metroStopIds
        let atac = atacRaw.filter { !metroIds.contains($0.stopId) }.map(SearchStopResult.atac)
        metroExcludedFromSearch = atac.count < atacRaw.count
        searchResults = cotral + atac
    }

    private func select(_ result: SearchStopResult) {
        switch result {
        case .cotral(let stop):
            stopName = stop.stopName
            if stop.isRail {
                let candidates = gtfsStore.getRoutesForStop(stop.stopId)
                    .flatMap { CotralTrainRoute.directions(forGTFSRouteShortName: $0.routeShortName) ?? [] }
                trainDirectionCandidates = candidates
                source = candidates.first.map { .cotralTrain(stationName: stop.stopName, route: $0) }
            } else {
                trainDirectionCandidates = []
                source = .cotralBus(poleCode: stop.stopId)
            }
        case .atac(let stop):
            stopName = stop.stopName
            trainDirectionCandidates = []
            source = .atacStop(stopId: stop.stopId)
        }
        searchText = ""
        searchResults = []
    }

    private func save() {
        guard let source else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
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
