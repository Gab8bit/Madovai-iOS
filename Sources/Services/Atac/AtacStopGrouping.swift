import Foundation

/// One physical station's platforms, grouped by name — see
/// `groupedStopsByName`'s doc comment for why these are kept together
/// rather than collapsed into one `AtacStop`.
struct AtacStopGroup: Identifiable {
    let name: String
    let stops: [AtacStop]
    var id: String { name }

    /// Representative platform used to place a single map pin (or stand in
    /// for the group wherever only one coordinate/id is needed) —
    /// arbitrary but deterministic (`stops` is pre-sorted by `stopId`).
    var anchor: AtacStop { stops[0] }
}

/// Groups stops by name, keeping every stop_id — a real Atac/Roma TPL
/// station is frequently split across several GTFS `stop_id`s, one physical
/// platform per direction of travel. An earlier version of this app mistook
/// that for duplicate/noisy data and silently discarded one of each pair —
/// wrong: each platform is real, distinctly-located data with its own
/// genuine real-time predictions, and dropping one just threw away a whole
/// direction's worth of arrivals. Grouping (rather than deduping) keeps all
/// of it, letting the UI offer a direction picker between them instead —
/// used both by the "Linee" station list and by the map's own pins/search
/// results, so a station like "Colosseo" reads as one place everywhere,
/// not once per platform.
func groupedStopsByName(_ stops: [AtacStop]) -> [AtacStopGroup] {
    var order: [String] = []
    var groups: [String: [AtacStop]] = [:]
    for stop in stops {
        let key = stop.stopName.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { continue }
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(stop)
    }
    return order.map { name in
        AtacStopGroup(name: name, stops: (groups[name] ?? []).sorted { $0.stopId < $1.stopId })
    }
}
