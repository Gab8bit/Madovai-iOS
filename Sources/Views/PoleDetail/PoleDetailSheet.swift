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
    @State private var selectedLiveDirection: CotralTrainRoute?

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
        switch viewModel.state {
        case .idle, .loading:
            if viewModel.transits.isEmpty {
                Spacer()
                LoadingOverlay(message: "Carico i transiti…")
                Spacer()
            } else {
                liveTransitsContent
            }
        case .loaded:
            liveTransitsContent
        case .empty:
            if let directions = viewModel.scheduledDeparturesByDirection, !directions.isEmpty {
                scheduledDeparturesView(directions)
            } else {
                Spacer()
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "Nessun transito disponibile",
                    message: viewModel.pole.isTreno
                        ? "Al momento Cotral non ha transiti in tempo reale per questa stazione, e non risultano corse programmate per il resto di oggi."
                        : "Riprova più tardi o controlla un'altra palina."
                )
                Spacer()
            }
        case .error(let message):
            Spacer()
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Errore", message: message)
            Spacer()
        }
    }

    /// Shown when Cotral's live PIV.do has nothing for this stop right now
    /// (tier 1 of the fallback failed) — a schedule instead, from either the
    /// cotralspa.it widget or the static GTFS timetable (see
    /// `PoleDetailViewModel.scheduledDeparturesByDirection`). Neither
    /// source is genuinely live (the widget's own "realtime" naming is
    /// misleading — every sample ever seen just says "In orario"), so both
    /// get the same honest "not live" labeling here — already filtered to
    /// what's still ahead of the current time, split by direction with a
    /// segmented control when there's more than one, and the very next
    /// departure of the selected direction called out explicitly.
    private func scheduledDeparturesView(_ directions: [TrainScheduleDirection]) -> some View {
        let current = directions.first { $0.destination == selectedDirection } ?? directions[0]

        return VStack(spacing: 0) {
            Label("Orari da tabella, non in tempo reale", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))

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
                    HStack {
                        Text(departure.time)
                            .font(.headline.monospacedDigit())
                        if departure.id == nextId {
                            Text("Prossimo treno")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
    }

    /// Live transits (tier 1) — split by direction for a Cotral rail pole
    /// when every current transit's `percorso` resolves to a known route
    /// (see `PoleDetailViewModel.liveTransitsByDirection`), otherwise the
    /// plain unsplit list (buses, or a rail percorso this app doesn't
    /// recognize).
    @ViewBuilder
    private var liveTransitsContent: some View {
        if let directions = viewModel.liveTransitsByDirection, directions.count > 1 {
            liveTransitDirectionsView(directions)
        } else {
            transitList
        }
    }

    private func liveTransitDirectionsView(_ directions: [(route: CotralTrainRoute, transits: [Transit])]) -> some View {
        let current = directions.first { $0.route == selectedLiveDirection } ?? directions[0]

        return VStack(spacing: 0) {
            Picker("Direzione", selection: Binding(
                get: { selectedLiveDirection ?? directions[0].route },
                set: { selectedLiveDirection = $0 }
            )) {
                ForEach(directions, id: \.route) { direction in
                    Text(direction.route.destinationName).tag(direction.route)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            List(current.transits) { transit in
                TransitRowView(
                    transit: transit,
                    isFollowing: vehicleTracker.isFollowing(transit.automezzo.codice ?? ""),
                    onToggleFollow: {
                        guard let code = transit.automezzo.codice else { return }
                        vehicleTracker.toggleFollowing(code)
                    }
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }

    private var transitList: some View {
        List(viewModel.transits) { transit in
            TransitRowView(
                transit: transit,
                isFollowing: vehicleTracker.isFollowing(transit.automezzo.codice ?? ""),
                onToggleFollow: {
                    guard let code = transit.automezzo.codice else { return }
                    vehicleTracker.toggleFollowing(code)
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
                    Text("Seguendo bus \(vehicleCode)")
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
