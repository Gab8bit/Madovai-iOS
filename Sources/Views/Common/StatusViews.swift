import SwiftUI

/// Rounded "glass" card used by every banner floating over the map.
struct BannerCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal)
    }
}

/// A problem with an optional "Riprova" (network error, server not ready…).
struct ErrorBanner: View {
    var title = "Errore di connessione"
    let message: String
    var systemImage = "wifi.exclamationmark"
    var tint: Color = .red
    var retry: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        BannerCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.bold())
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let retry {
                    Button("Riprova", action: retry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if let dismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chiudi")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Small non-blocking "Caricamento dati…" pill.
struct LoadingPill: View {
    var text = "Caricamento dati…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// Informational one-liner floating over the map ("Avvicina la mappa…").
struct HintPill: View {
    let text: String
    var systemImage = "plus.magnifyingglass"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

/// Centered spinner + text for sheets and lists.
struct LoadingStateView: View {
    var message = "Caricamento…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    var systemImage = "tram"
    var title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Full-area error with retry, for a sheet that has nothing to show yet.
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        EmptyStateView(
            systemImage: "wifi.exclamationmark",
            title: "Impossibile caricare i dati",
            message: message,
            actionTitle: retry == nil ? nil : "Riprova",
            action: retry
        )
        .frame(maxHeight: .infinity)
    }
}

/// Thin strip at the top of a sheet whose data is shown but stale because
/// the last refresh failed.
struct StaleDataStrip: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("Aggiornamento non riuscito: \(message)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let retry {
                Button("Riprova", action: retry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
}

/// Small coloured status dot; `pulse` marks genuinely live data.
struct StatusDot: View {
    var color: Color
    var pulse = false
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(pulse && isPulsing ? 1.5 : 1)
            .opacity(pulse && isPulsing ? 0.5 : 1)
            .onAppear {
                guard pulse else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
            }
            .accessibilityHidden(true)
    }
}

struct CapsuleTag: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

/// Header shared by every stop/vehicle sheet: title, subtitle, optional star.
struct SheetHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var isFavorite: Bool?
    var toggleFavorite: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title).font(.title3.bold())
                }
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let isFavorite, let toggleFavorite {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti")
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// Periodic redraw so "tra N min" labels stay current between data refreshes.
struct MinuteTicker<Content: View>: View {
    var interval: TimeInterval = 20
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            content(context.date)
        }
    }
}
