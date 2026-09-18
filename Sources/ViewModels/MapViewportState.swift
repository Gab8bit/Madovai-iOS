import MapKit

/// Debounces `MKMapView` region-change events into a single "settled"
/// bounding box that Cotral poles, Atac stops/shapes, and the opportunistic
/// Cotral vehicle scan all react to — so a drag or pinch gesture doesn't
/// fire a burst of network requests per frame.
@MainActor
final class MapViewportState: ObservableObject {
    @Published private(set) var settledBounds: ViewportBounds?

    private var debounceTask: Task<Void, Never>?

    func regionChanged(_ region: MKCoordinateRegion) {
        let bounds = ViewportBounds(region: region)
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Config.viewportSettleDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.settledBounds = bounds
        }
    }
}
