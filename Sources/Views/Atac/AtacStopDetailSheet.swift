import SwiftUI

/// Predictions here are primarily realtime-derived; when a stop has no live
/// `trip_updates` prediction at all, `AtacGtfsStore.scheduledDepartures`
/// provides a best-effort static-timetable fallback instead (marked
/// `isScheduled` on the resulting `AtacStopPrediction`s) — see that method's
/// doc comment for what it can't account for (mainly overnight runs still
/// under yesterday's service_id).
struct AtacStopDetailSheet: View {
    let stop: AtacStop
    @ObservedObject var realtimeService: AtacRealtimeService
    let atacGtfsStore: AtacGtfsStore

    @State private var scheduledFallback: [AtacStopPrediction] = []
    @State private var isLoadingFallback = false

    private var livePredictions: [AtacStopPrediction] {
        realtimeService.stopPredictions[stop.stopId] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .task(id: stop.stopId) {
            guard livePredictions.isEmpty else { return }
            isLoadingFallback = true
            defer { isLoadingFallback = false }
            scheduledFallback = (try? await atacGtfsStore.scheduledDepartures(forStopId: stop.stopId)) ?? []
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stop.stopName)
                .font(.title3.bold())
            Text("Atac / Roma TPL · tempo reale")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

            if prediction.isScheduled {
                Text("stimato")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let delaySeconds = prediction.delaySeconds, abs(delaySeconds) >= 60 {
                Text(delayLabel(delaySeconds))
                    .font(.caption)
                    .foregroundStyle(delaySeconds > 0 ? .red : .green)
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
