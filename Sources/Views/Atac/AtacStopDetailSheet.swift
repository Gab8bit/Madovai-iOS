import SwiftUI

/// Predictions here are primarily realtime-derived; when a stop has no live
/// `trip_updates` prediction at all, `AtacGtfsStore.scheduledDepartures`
/// provides a best-effort static-timetable fallback instead (marked
/// `isScheduled` on the resulting `AtacStopPrediction`s) — see that method's
/// doc comment for what it can't account for (mainly overnight runs still
/// under yesterday's service_id).
///
/// `stops` can hold more than one `AtacStop` — a real station is often split
/// across several GTFS `stop_id`s, one physical platform per direction of
/// travel (what an earlier version of this app mistook for "duplicate"
/// stops and silently collapsed into one, discarding real data). When there
/// is more than one, a segmented control lets the user switch between them,
/// labeled by each platform's own direction rather than a meaningless
/// repeated station name.
struct AtacStopDetailSheet: View {
    let stops: [AtacStop]
    /// The line context to resolve each stop's direction label from, when
    /// known (e.g. opened from a specific line's own station list) — nil
    /// when this sheet was opened from a bare map-pin tap or search result
    /// with no specific line in mind, in which case `headsign(for:)` falls
    /// back to any route's headsign for that platform instead.
    let routeId: String?
    @ObservedObject var realtimeService: AtacRealtimeService
    let atacGtfsStore: AtacGtfsStore
    @ObservedObject var favoritesStore: FavoritesStore

    @State private var selectedStopId: String?
    @State private var scheduledFallback: [AtacStopPrediction] = []
    @State private var isLoadingFallback = false

    private var selectedStop: AtacStop {
        stops.first { $0.stopId == selectedStopId } ?? stops[0]
    }

    private var livePredictions: [AtacStopPrediction] {
        realtimeService.stopPredictions[selectedStop.stopId] ?? []
    }

    private func headsign(for stop: AtacStop) -> String? {
        if let routeId {
            return atacGtfsStore.headsign(forRouteId: routeId, stopId: stop.stopId)
        }
        return atacGtfsStore.anyHeadsign(forStopId: stop.stopId)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if stops.count > 1 {
                directionPicker
            }
            Divider()
            if !livePredictions.isEmpty {
                List(livePredictions) { prediction in
                    AtacPredictionRow(prediction: prediction)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            } else if isLoadingFallback {
                Spacer()
                ProgressView("Cerco gli orari in programma…")
                Spacer()
            } else if !scheduledFallback.isEmpty {
                List {
                    Label("Nessun mezzo in tempo reale al momento: questi sono orari stimati da programmazione.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                    ForEach(scheduledFallback) { prediction in
                        AtacPredictionRow(prediction: prediction)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            } else {
                Spacer()
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "Nessun transito in tempo reale",
                    message: "Questa fermata potrebbe non avere corse attive in questo momento."
                )
                Spacer()
            }
        }
        .task(id: selectedStop.stopId) {
            guard livePredictions.isEmpty else { return }
            isLoadingFallback = true
            defer { isLoadingFallback = false }
            scheduledFallback = (try? await atacGtfsStore.scheduledDepartures(forStopId: selectedStop.stopId)) ?? []
        }
    }

    private var directionPicker: some View {
        Picker("Direzione", selection: Binding(
            get: { selectedStopId ?? stops[0].stopId },
            set: { selectedStopId = $0 }
        )) {
            ForEach(stops) { stop in
                Text(headsign(for: stop) ?? stop.stopName).tag(stop.stopId)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stops[0].stopName)
                    .font(.title3.bold())
                Text("Atac / Roma TPL · tempo reale")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Favorites the platform currently selected (same per-stop_id
            // granularity Cotral's own star already uses) — switching the
            // direction picker switches which one the star reflects.
            Button {
                favoritesStore.toggle(selectedStop)
            } label: {
                Image(systemName: favoritesStore.isFavorite(atacStopId: selectedStop.stopId) ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

private struct AtacPredictionRow: View {
    let prediction: AtacStopPrediction

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(prediction.arrivalTimeLabel)
                    .font(.title3.bold().monospacedDigit())
                Text(relativeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .leading)

            VStack(spacing: 2) {
                Image(systemName: prediction.kind.sfSymbolName)
                Text(prediction.routeLabel)
                    .font(.caption.weight(.bold))
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 2) {
                if let headsign = prediction.headsign, !headsign.isEmpty {
                    Text("verso \(headsign)")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                if prediction.isScheduled {
                    Text("stimato")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let delaySeconds = prediction.delaySeconds, abs(delaySeconds) >= 60 {
                    Text(delayLabel(delaySeconds))
                        .font(.caption)
                        .foregroundStyle(delaySeconds > 0 ? .red : .green)
                }
            }

            Spacer()

            Circle().fill(prediction.isScheduled ? Color.gray : Color.green).frame(width: 7, height: 7)
        }
        .padding(.vertical, 4)
    }

    private var relativeLabel: String {
        let minutes = prediction.minutesFromNow
        if prediction.isScheduled { return "tra \(max(minutes, 0)) min" }
        if minutes <= 0 { return "in arrivo" }
        if minutes == 1 { return "tra 1 min" }
        return "tra \(minutes) min"
    }

    private func delayLabel(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return seconds > 0 ? "in ritardo di \(minutes) min" : "in anticipo di \(minutes) min"
    }
}
