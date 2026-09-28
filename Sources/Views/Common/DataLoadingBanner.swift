import SwiftUI

/// Compact, non-blocking status for the GTFS stores' first-launch
/// download/extract/parse — shown as an overlay on top of an already-usable
/// map (unlike the old `GTFSLoadingView` it replaced, which blocked the
/// whole screen until Cotral's own store was ready). One row per store
/// that isn't `.ready` yet; disappears once both are. A determinate
/// progress bar during `.downloading` when the server reported a content
/// length (Atac's ~47MB zip is the one worth it), otherwise an
/// indeterminate spinner.
struct DataLoadingBanner: View {
    struct Item: Identifiable {
        let id: String
        let label: String
        let state: GTFSLoadingState
        let progress: Double?
        let retry: () -> Void
    }

    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                row(for: item)
            }
            // Phase-agnostic on purpose — this banner also shows during
            // `.parsing` (which runs on *every* launch, cache or not, to
            // turn the already-downloaded GTFS files back into in-memory
            // models) and `.extracting`, not just `.downloading`. Naming
            // "download" specifically here made every ordinary relaunch
            // look like a fresh download even when the cache was reused
            // untouched (confirmed live: file mtimes unchanged across a
            // terminate+relaunch cycle) — each row's own `phaseLabel`
            // already says which phase is actually active.
            Text("Percorsi, linee e altri dati potrebbero non essere ancora disponibili finché il caricamento non è completo.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func row(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                if let progress = item.progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = item.state {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("Riprova", action: item.retry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            } else {
                if let progress = item.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
                Text(phaseLabel(item.state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func phaseLabel(_ state: GTFSLoadingState) -> String {
        switch state {
        case .idle: return "In attesa…"
        case .downloading: return "Scaricamento…"
        case .extracting: return "Estrazione…"
        case .parsing: return "Elaborazione…"
        case .ready, .failed: return ""
        }
    }
}
