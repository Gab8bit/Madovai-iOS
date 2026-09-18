import SwiftUI

struct StopLineSearchBar: View {
    @ObservedObject var viewModel: MapViewModel
    var onSelectStop: (SearchStopResult) -> Void
    var onSelectRoute: (SearchRouteResult) -> Void

    @FocusState private var isFocused: Bool

    private var hasResults: Bool {
        !viewModel.stopResults.isEmpty || !viewModel.routeResults.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Cerca una fermata o una linea…", text: $viewModel.searchText)
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.searchText) { _ in
                        viewModel.search()
                    }
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.clearSearch()
                        isFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if isFocused && hasResults {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !viewModel.routeResults.isEmpty {
                            sectionHeader("Linee")
                            ForEach(viewModel.routeResults) { route in
                                resultRow(
                                    icon: route.iconName,
                                    title: route.displayName,
                                    subtitle: [route.subtitle, route.longName].filter { !$0.isEmpty }.joined(separator: " · ")
                                ) {
                                    isFocused = false
                                    onSelectRoute(route)
                                }
                                if route.id != viewModel.routeResults.last?.id {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                        if !viewModel.stopResults.isEmpty {
                            sectionHeader("Fermate")
                            ForEach(viewModel.stopResults) { stop in
                                resultRow(icon: stop.iconName, title: stop.name, subtitle: stop.subtitle) {
                                    isFocused = false
                                    onSelectStop(stop)
                                }
                                if stop.id != viewModel.stopResults.last?.id {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 6)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.15), value: viewModel.stopResults)
        .animation(.easeInOut(duration: 0.15), value: viewModel.routeResults)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func resultRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        // Without this, a bare `Button` tints its whole label with the
        // accent color, overriding the `.primary`/`.secondary` foreground
        // styles above — washed-out, low-contrast text in dark mode
        // specifically (confirmed against a real dark-mode screenshot).
        .buttonStyle(.plain)
    }
}
