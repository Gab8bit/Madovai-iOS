import Foundation

/// The 6 `codicePercorso` values accepted by Cotral's train-schedule widget
/// endpoint (`cotralspa.it/wp-json/cotral/v1/get-train-stopsroute`) — one
/// per direction of each of the 3 rail lines it covers. This is a
/// completely separate, unrelated backend from PIV.do/Automezzi.do (see
/// `CotralTrainScheduleClient`) and from GTFS's own `route_id`s — these
/// codes only mean something to this one endpoint.
enum CotralTrainRoute: String, CaseIterable, Identifiable, Hashable {
    case metromareColomboToPortaSanPaolo = "RL_CC-PSP"
    case metromarePortaSanPaoloToColombo = "RL_PSP-CC"
    case viterboUrbanaFlaminioToMontebello = "RN_RMMON"
    case viterboUrbanaMontebelloToFlaminio = "RN_MONRM"
    case viterboExtraurbanaCatalanoToViterbo = "RV_CATVIT"
    case viterboExtraurbanaViterboToCatalano = "RV_VITCAT"

    var id: String { rawValue }

    var lineName: String {
        switch self {
        case .metromareColomboToPortaSanPaolo, .metromarePortaSanPaoloToColombo:
            return "Metromare"
        case .viterboUrbanaFlaminioToMontebello, .viterboUrbanaMontebelloToFlaminio:
            return "Roma-Viterbo Urbana"
        case .viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano:
            return "Roma-Viterbo Extraurbana"
        }
    }

    var directionLabel: String {
        switch self {
        case .metromareColomboToPortaSanPaolo: return "Cristoforo Colombo → Porta San Paolo"
        case .metromarePortaSanPaoloToColombo: return "Porta San Paolo → Cristoforo Colombo"
        case .viterboUrbanaFlaminioToMontebello: return "Flaminio → Montebello"
        case .viterboUrbanaMontebelloToFlaminio: return "Montebello → Flaminio"
        case .viterboExtraurbanaCatalanoToViterbo: return "Catalano → Viterbo"
        case .viterboExtraurbanaViterboToCatalano: return "Viterbo → Catalano"
        }
    }

    /// Just the terminus this direction is heading towards (the second half
    /// of `directionLabel`) — used wherever a clean, short direction label
    /// is needed instead of the full "A → B" sentence, e.g. as a segmented
    /// picker's tag text or in place of the raw `codicePercorso` PIV.do
    /// echoes back verbatim in a live transit's `percorso` field.
    var destinationName: String {
        switch self {
        case .metromareColomboToPortaSanPaolo: return "Porta San Paolo"
        case .metromarePortaSanPaoloToColombo: return "Cristoforo Colombo"
        case .viterboUrbanaFlaminioToMontebello: return "Montebello"
        case .viterboUrbanaMontebelloToFlaminio: return "Flaminio"
        case .viterboExtraurbanaCatalanoToViterbo: return "Viterbo"
        case .viterboExtraurbanaViterboToCatalano: return "Catalano"
        }
    }

    /// The GTFS rail route (`route_short_name`, e.g. "ROMALIDO") this
    /// direction's line corresponds to — the inverse of
    /// `directions(forGTFSRouteShortName:)`, used to look up that route's
    /// drawable shape for the map.
    var gtfsRouteShortName: String {
        switch self {
        case .metromareColomboToPortaSanPaolo, .metromarePortaSanPaoloToColombo: return "ROMALIDO"
        case .viterboUrbanaFlaminioToMontebello, .viterboUrbanaMontebelloToFlaminio: return "RVURB"
        case .viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano: return "RVEXT"
        }
    }

    /// The other direction of the same line — for a UI direction switcher.
    var reversed: CotralTrainRoute {
        switch self {
        case .metromareColomboToPortaSanPaolo: return .metromarePortaSanPaoloToColombo
        case .metromarePortaSanPaoloToColombo: return .metromareColomboToPortaSanPaolo
        case .viterboUrbanaFlaminioToMontebello: return .viterboUrbanaMontebelloToFlaminio
        case .viterboUrbanaMontebelloToFlaminio: return .viterboUrbanaFlaminioToMontebello
        case .viterboExtraurbanaCatalanoToViterbo: return .viterboExtraurbanaViterboToCatalano
        case .viterboExtraurbanaViterboToCatalano: return .viterboExtraurbanaCatalanoToViterbo
        }
    }

    /// Both directions of the line that GTFS route (by its
    /// `route_short_name`) belongs to — used to go from a GTFS-derived rail
    /// `Pole` to the codes this endpoint needs. GTFS's own rail
    /// `stop_id`/`route_id` namespacing doesn't cleanly map here: both
    /// Roma-Viterbo lines share the same "RN_" stop prefix (only the route
    /// tells them apart), which is why this matches on the route instead of
    /// the stop id (confirmed against the real rail `routes.txt`:
    /// `ROMALIDO`/`RVEXT`/`RVURB`).
    static func directions(forGTFSRouteShortName shortName: String) -> [CotralTrainRoute]? {
        switch shortName.uppercased() {
        case "ROMALIDO": return [.metromareColomboToPortaSanPaolo, .metromarePortaSanPaoloToColombo]
        case "RVURB": return [.viterboUrbanaFlaminioToMontebello, .viterboUrbanaMontebelloToFlaminio]
        case "RVEXT": return [.viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano]
        default: return nil
        }
    }
}
