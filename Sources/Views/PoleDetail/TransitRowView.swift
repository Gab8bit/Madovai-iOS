import SwiftUI

struct TransitRowView: View {
    let transit: Transit
    let isFollowing: Bool
    var onToggleFollow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel)
                    .font(.title3.bold().monospacedDigit())
                if let relative = relativeLabel {
                    Text(relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(destinationLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                statusRow

                if transit.instradamento.isEmpty == false {
                    Text(transit.instradamento)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if transit.canTrackVehicle {
                Button(action: onToggleFollow) {
                    VStack(spacing: 4) {
                        Image(systemName: isFollowing ? "location.fill" : "location")
                        Text(isFollowing ? "Seguito" : "Segui")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .tint(isFollowing ? .orange : .accentColor)
            }
        }
        .padding(.vertical, 6)
    }

    private var timeLabel: String {
        transit.displayTime.isEmpty ? "--:--" : transit.displayTime
    }

    private var relativeLabel: String? {
        guard let minutes = transit.minutesFromNow else { return nil }
        if minutes <= 0 { return "in transito" }
        if minutes == 1 { return "tra 1 min" }
        return "tra \(minutes) min"
    }

    private var destinationLabel: String {
        // Cotral appends an internal code in parens to a train's own
        // destination name (e.g. "Cristoforo Colombo (ff90006)") — not
        // meaningful to a rider, so it's stripped the same way a GTFS stop
        // name's own parenthetical/pipe suffixes already are elsewhere.
        let destination = transit.arrivoCorsa.isEmpty ? "Destinazione N/D" : GTFSTextUtils.extractLocalityFromStopName(transit.arrivoCorsa)
        // For a Cotral train, `percorso` literally is one of the 6 internal
        // route codes cotralspa.it's own schedule widget uses (e.g.
        // "RL_PSP-CC") — not meaningful to a rider, so it's dropped rather
        // than shown raw. Bus `percorso` values are kept as-is (unchanged
        // behavior): those are the line's own route identifier.
        guard CotralTrainRoute(rawValue: transit.percorso) == nil else { return destination }
        return transit.percorso.isEmpty ? destination : "\(transit.percorso) · \(destination)"
    }

    @ViewBuilder
    private var statusRow: some View {
        switch transit.trackingStatus {
        case .realtime:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("Real-time · \(delayText)")
                    .font(.caption)
                    .foregroundStyle(delayColor)
            }
        case .monitoredOffline:
            HStack(spacing: 4) {
                Circle().fill(Color.yellow).frame(width: 7, height: 7)
                Text("Tracciata, bus non in trasmissione")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .scheduled:
            HStack(spacing: 4) {
                Circle().fill(Color.gray).frame(width: 7, height: 7)
                Text("Schedulata, no real-time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A difference under a minute isn't worth surfacing as a delay/advance
    /// — it just means the run is on time. `ritardo` is only meaningful in
    /// the realtime state to begin with — see `Transit.isDelayReliable`.
    private var delayText: String {
        guard transit.isDelayReliable, abs(transit.ritardoSeconds) >= 60 else { return "puntuale" }
        let minutes = abs(transit.ritardoSeconds) / 60
        return transit.ritardoSeconds > 0 ? "in ritardo di \(minutes) min" : "in anticipo di \(minutes) min"
    }

    private var delayColor: Color {
        guard transit.isDelayReliable, abs(transit.ritardoSeconds) >= 60 else { return .secondary }
        return transit.ritardoSeconds > 0 ? .red : .green
    }
}
