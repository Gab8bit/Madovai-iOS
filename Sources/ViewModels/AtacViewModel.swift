import Foundation

/// Drives the Atac/Roma TPL map layer: which stops/line shapes are visible
/// for the current viewport, plus the show/hide toggle for the lines
/// overlay (stops stay visible regardless — only the lines can get heavy
/// with many routes overlapping at wide zoom).
@MainActor
final class AtacViewModel: ObservableObject {
    @Published private(set) var visibleStops: [AtacStop] = []
    @Published private(set) var visibleShapes: [AtacLineShape] = []
    @Published var linesVisible: Bool = true

    private let gtfsStore: AtacGtfsStore

    init(gtfsStore: AtacGtfsStore) {
        self.gtfsStore = gtfsStore
    }

    func updateViewport(_ bounds: ViewportBounds) {
        guard gtfsStore.state == .ready else { return }
        let padded = bounds.padded
        visibleStops = gtfsStore.stopsInRegion(minLat: padded.minLat, maxLat: padded.maxLat, minLon: padded.minLon, maxLon: padded.maxLon)
        visibleShapes = linesVisible
            ? gtfsStore.shapesInRegion(minLat: padded.minLat, maxLat: padded.maxLat, minLon: padded.minLon, maxLon: padded.maxLon)
            : []
    }

    func toggleLinesVisible(bounds: ViewportBounds?) {
        linesVisible.toggle()
        if let bounds { updateViewport(bounds) }
    }
}
