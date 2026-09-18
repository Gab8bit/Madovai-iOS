import Foundation

/// One scheduled passage at a station, as shown by Cotral's train-schedule
/// widget (`CotralTrainScheduleClient`/`CotralTrainScheduleParser`).
/// `status` is whatever label the source sends verbatim — on a sample of
/// 500+ real entries across all 3 lines it was always "In orario" (on
/// time), with no delay/cancellation variant ever observed, and no train
/// id or GPS anywhere in the payload. So despite the endpoint's URL and
/// markup both saying "realtime", treat this as a **published timetable
/// with a generic status tag**, not per-train live tracking — don't infer
/// or display more precision (e.g. "in ritardo di 3 minuti") than the
/// source literally provides. If a genuinely different status string shows
/// up in the wild, it'll just be surfaced here as-is; no allow-list.
struct CotralTrainPassage: Identifiable, Hashable {
    let time: String
    let status: String

    var id: String { time + "-" + status }
}

/// All of one direction's scheduled passages at a single station.
struct CotralTrainStationSchedule: Identifiable, Hashable {
    let stationName: String
    let passages: [CotralTrainPassage]

    var id: String { stationName }
}
