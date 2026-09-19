import SwiftUI

/// The sheet's content. `viewModel` is owned one level up (by
/// `PoleDetailSheetContainer` in ContentView.swift) so it can outlive
/// SwiftUI's sheet-presentation churn if needed; `vehicleTracker` is the
/// single app-wide tracker (also owned at the root) so the map marker keeps
/// animating even after this sheet is dismissed.
struct PoleDetailSheetBody: View {
    @ObservedObject var viewModel: PoleDetailViewModel
    @ObservedObject var favoritesStore: FavoritesStore
    @ObservedObject var vehicleTracker: VehicleTracker
    @State private var selectedDirection: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let trackedVehicleCode = vehicleTracker.vehicleCode {
                vehicleTrackingBanner(vehicleCode: trackedVehicleCode)
            }

            Divider()

            content
        }
        .onAppear { viewModel.startObservingTransits() }
        .onDisappear { viewModel.stopObservingTransits() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.pole.displayName)
                    .font(.title3.bold())
                if let subtitle = viewModel.pole.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let poleCode = viewModel.pole.codicePalina {
                Button {
                    favoritesStore.toggle(viewModel.pole)
                } label: {
                    Image(systemName: favoritesStore.isFavorite(poleCode) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.pole.isTreno {
            railContent
        } else {
            busContent
        }
    }

    /// Cotral bus poles: unchanged — live PIV.do transits, with "Segui" to
    /// track a vehicle on the map.
    @ViewBuilder
    private var busContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            if viewModel.transits.isEmpty {
                Spacer()
                LoadingOverlay(message: "Carico i transiti…")
                Spacer()
            } else {
                transitList
            }
        case .loaded:
            transitList
        case .empty:
            Spacer()
            EmptyStateView(
                systemImage: "clock.badge.questionmark",
                title: "Nessun transito disponibile",
                message: "Riprova più tardi o controlla un'altra palina."
            )
            Spacer()
        case .error(let message):
            Spacer()
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Errore", message: message)
            Spacer()
        }
    }

    /// Cotral rail poles: ASTRAL's schedule (real per-run delay,
    /// cancellations, replacement-bus service — see
    /// `PoleDetailViewModel.scheduledDeparturesByDirection`), falling back
    /// to the static GTFS timetable only if ASTRAL has nothing at all for
    /// this station. No "Segui" here — ASTRAL has no vehicle/GPS data to
    /// follow (a moving train marker on the map, when PIV.do happens to
    /// have one, is still followable from there, unaffected by this).
    @ViewBuilder
    private var railContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            if let directions = viewModel.scheduledDeparturesByDirection, !directions.isEmpty {
                railScheduleView(directions)
            } else {
                Spacer()
                LoadingOverlay(message: "Carico gli orari…")
                Spacer()
            }
        case .loaded, .empty:
            if let directions = viewModel.scheduledDeparturesByDirection, !directions.isEmpty {
                railScheduleView(directions)
            } else {
                Spacer()
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "Nessun transito disponibile",
                    message: "Al momento non risultano corse per questa stazione, in tempo reale né programmate, per il resto di oggi."
                )
                Spacer()
            }
        case .error(let message):
            Spacer()
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Errore", message: message)
            Spacer()
        }
    }

    private func railScheduleView(_ directions: [AstralScheduleDirection]) -> some View {
        let current = directions.first { $0.destination == selectedDirection } ?? directions[0]
        // A direction whose entries carry no known delay at all is one that
        // fell through to the static-GTFS tier (ASTRAL couldn't resolve
        // this station) — genuine ASTRAL data almost always has a delay
        // figure even when it's "0" (confirmed live: only a just-inserted
        // reinforcement run briefly has none), so this is a reliable enough
        // signal to label the two cases honestly without threading a
        // separate "which tier" flag through the view model.
        let isEstimate = !current.entries.contains { $0.delayMinutes != nil }

        return VStack(spacing: 0) {
            if isEstimate {
                Label("Orario stimato da tabella, non in tempo reale", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08))
            }

            if directions.count > 1 {
                Picker("Direzione", selection: Binding(
                    get: { selectedDirection ?? directions[0].destination },
                    set: { selectedDirection = $0 }
                )) {
                    ForEach(directions) { direction in
                        Text(direction.destination).tag(direction.destination)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
            } else {
                Text("Verso \(current.destination)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            if current.entries.isEmpty {
                Spacer()
                EmptyStateView(
                    systemImage: "moon.zzz",
                    title: "Corse terminate per oggi",
                    message: "Non risultano altre corse programmate verso \(current.destination) per il resto di oggi."
                )
                Spacer()
            } else {
                let nextId = current.entries.first?.id
                List(current.entries) { departure in
                    AstralDepartureRow(departure: departure, isNext: departure.id == nextId)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
    }

    private var transitList: some View {
        List(viewModel.transits) { transit in
            TransitRowView(
                transit: transit,
                isFollowing: vehicleTracker.isFollowing(transit.automezzo.codice ?? ""),
                onToggleFollow: {
                    guard let code = transit.automezzo.codice else { return }
                    vehicleTracker.toggleFollowing(code, isTreno: viewModel.pole.isTreno)
                }
            )
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private func vehicleTrackingBanner(vehicleCode: String) -> some View {
        HStack(spacing: 10) {
            switch vehicleTracker.state {
            case .tracking:
                Image(systemName: "location.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Seguendo \(vehicleTracker.isTreno ? "treno" : "bus") \(vehicleCode)")
                        .font(.footnote.weight(.semibold))
                    Text("Posizione aggiornata ogni \(Int(Config.vehiclePositionPollInterval))s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .lost:
                Image(systemName: "location.slash.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tracking interrotto")
                        .font(.footnote.weight(.semibold))
                    Text("Il veicolo \(vehicleCode) non trasmette più la posizione")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .idle:
                EmptyView()
            }

            Spacer()

            Button("Ferma") { vehicleTracker.stopFollowing() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(bannerBackground)
    }

    private var bannerBackground: Color {
        switch vehicleTracker.state {
        case .lost: return Color.red.opacity(0.12)
        default: return Color.orange.opacity(0.12)
        }
    }
}

/// Same time/status layout as `TransitRowView` on the PIV.do/bus side (big
/// time + "tra N min" on the left, a colored status dot + delay text in the
/// middle) so a rail row doesn't read as a stripped-down version of a bus
/// one — ASTRAL just fills in different fields (no destination here, it's
/// already shown once above via the direction picker; no vehicle to follow).
private struct AstralDepartureRow: View {
    let departure: AstralDeparture
    let isNext: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(departure.time)
                    .font(.title3.bold().monospacedDigit())
                if let relative = relativeLabel {
                    Text(relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                statusRow
                if departure.isReplacementBus {
                    Label("Bus sostitutivo", systemImage: "bus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if departure.isCancelled {
                Text("Soppressa")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
            } else if isNext {
                Text("Prossimo treno")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .opacity(departure.isCancelled ? 0.6 : 1)
        .padding(.vertical, 6)
    }

    private var relativeLabel: String? {
        guard let minutes = Transit.minutesFromNow(departure.time) else { return nil }
        if minutes <= 0 { return "in arrivo" }
        if minutes == 1 { return "tra 1 min" }
        return "tra \(minutes) min"
    }

    /// Mirrors `TransitRowView.statusRow`'s colored-dot + label shape:
    /// green when ASTRAL reported a real delay (even 0, i.e. "puntuale"),
    /// gray when this entry has none — either the static-GTFS fallback tier,
    /// or a just-inserted reinforcement run ASTRAL hasn't computed one for
    /// yet. Nothing shown for a cancelled run; the trailing "Soppressa" tag
    /// already covers that.
    @ViewBuilder
    private var statusRow: some View {
        if departure.isCancelled {
            EmptyView()
        } else if let minutes = departure.delayMinutes {
            HStack(spacing: 6) {
                PulsingDot(color: .green)
                Text(delayText(minutes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(delayColor(minutes))
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: minutes)
            }
        } else {
            HStack(spacing: 6) {
                Circle().fill(Color.gray).frame(width: 7, height: 7)
                Text("Schedulata")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A difference under a minute isn't worth surfacing — same threshold
    /// as `TransitRowView.delayText` on the PIV.do/bus side.
    private func delayText(_ minutes: Int) -> String {
        if abs(minutes) < 1 { return "Puntuale" }
        return minutes > 0 ? "In ritardo di \(minutes) min" : "In anticipo di \(abs(minutes)) min"
    }

    private func delayColor(_ minutes: Int) -> Color {
        if abs(minutes) < 1 { return .secondary }
        return minutes > 0 ? .red : .green
    }
}

/// A softly breathing dot marking data as genuinely live (ASTRAL-sourced),
/// distinct from the still gray dot used for the static-GTFS fallback tier.
private struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(isPulsing ? 1.5 : 1)
            .opacity(isPulsing ? 0.5 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
