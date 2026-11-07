import SwiftUI

/// "Cerca una fermata o una linea…" over the map: lines first, then stops,
/// across Cotral and Atac / Roma TPL (matching runs on the backend).
struct StopLineSearchBar: View {
    @ObservedObject var model: SearchModel
    var onSelectStop: (SearchStop) -> Void
    var onSelectRoute: (RouteInfo) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Cerca una fermata o una linea…", text: $model.query)
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if model.isSearching {
                    ProgressView().controlSize(.small)
                }
                if !model.query.isEmpty {
                    Button {
                        model.clear()
                        isFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancella")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)

            if isFocused && !model.trimmedQuery.isEmpty {
                results
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.15), value: model.hasResults)
    }

    @ViewBuilder
    private var results: some View {
        if model.hasResults {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !model.routes.isEmpty {
                        sectionHeader("Linee")
                        ForEach(model.routes) { route in
                            resultRow(
                                icon: route.iconName,
                                title: route.isMetro || route.rail ? route.title : "Linea \(route.title)",
                                subtitle: [route.operatorLabel, route.subtitleName].compactMap { $0 }.joined(separator: " · ")
                            ) {
                                select { onSelectRoute(route) }
                            }
                            .accessibilityIdentifier("search.route")
                        }
                    }
                    if !model.stops.isEmpty {
                        sectionHeader("Fermate")
                        ForEach(model.stops) { stop in
                            resultRow(icon: stop.iconName, title: stop.name, subtitle: stop.subtitle) {
                                select { onSelectStop(stop) }
                            }
                            .accessibilityIdentifier(stop.isCotral ? (stop.rail ? "search.stop.cotralRail" : "search.stop.cotralBus") : "search.stop.atac")
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let error = model.errorMessage {
            messageCard(icon: "wifi.exclamationmark", text: error, retry: model.retry)
        } else if !model.isSearching {
            messageCard(icon: "magnifyingglass", text: "Nessun risultato per \"\(model.trimmedQuery)\".", retry: nil)
        }
    }

    private func select(_ action: () -> Void) {
        isFocused = false
        action()
        model.clear()
    }

    private func messageCard(icon: String, text: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let retry {
                Button("Riprova", action: retry).font(.footnote.weight(.semibold))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func resultRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        // A bare Button tints its label with the accent colour, washing out
        // the primary/secondary text in dark mode.
        .buttonStyle(.plain)
    }
}
