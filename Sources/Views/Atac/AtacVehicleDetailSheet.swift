import SwiftUI

/// Shown when tapping an Atac/Roma TPL vehicle marker: the full stop-by-stop
/// schedule of its current run, built from the live `trip_updates` feed
/// (see `AtacRealtimeService.tripStopTimes`) — while this sheet is open the
/// map is also focused to just this vehicle's line (see `ContentView`).
struct AtacVehicleDetailSheet: View {
    let vehicle: TransitVehicle
    @ObservedObject var realtimeService: AtacRealtimeService

    private var stops: [AtacTripStopTime] {
        guard let tripId = vehicle.tripId else { return [] }
        return realtimeService.tripStopTimes[tripId] ?? []
    }

    /// Re-resolves the live vehicle each refresh (position/delay can change
    /// while the sheet is open) rather than freezing the tapped snapshot.
    private var liveVehicle: TransitVehicle {
        realtimeService.vehicles.first { $0.id == vehicle.id } ?? vehicle
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if stops.isEmpty {
                Spacer()
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "Orario non disponibile",
                    message: "Non ho ancora un aggiornamento in tempo reale per questa corsa."
                )
                Spacer()
            } else {
                List(stops) { stop in
                    AtacTripStopRow(stop: stop)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: liveVehicle.kind.sfSymbolName)
                Text("Linea \(liveVehicle.routeLabel ?? "—")")
                    .font(.title3.bold())
            }
            Text("\(liveVehicle.transitOperator.rawValue) · tempo reale")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

private struct AtacTripStopRow: View {
    let stop: AtacTripStopTime

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.stopName)
                    .font(.subheadline.weight(.semibold))
                if let delaySeconds = stop.delaySeconds, abs(delaySeconds) >= 60 {
                    Text(delayLabel(delaySeconds))
                        .font(.caption)
                        .foregroundStyle(delaySeconds > 0 ? .red : .green)
                }
            }
            Spacer()
            Text(stop.arrival, style: .time)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isPast ? .secondary : .primary)
        }
        .opacity(isPast ? 0.5 : 1)
        .padding(.vertical, 2)
    }

    private var isPast: Bool { stop.arrival < Date() }

    private func delayLabel(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return seconds > 0 ? "in ritardo di \(minutes) min" : "in anticipo di \(minutes) min"
    }
}
