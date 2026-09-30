import Foundation

/// The `codicePercorso` values ASTRAL's live-schedule API (and, before it,
/// Cotral's now-retired train-schedule widget) key rail schedules by — one
/// per direction of each rail line. This is a completely separate,
/// unrelated identifier space from PIV.do/Automezzi.do and from GTFS's own
/// `route_id`s — these codes only mean something to ASTRAL's API
/// (`AstralTrainClient`).
enum CotralTrainRoute: String, CaseIterable, Identifiable, Hashable, Codable {
    case metromareColomboToPortaSanPaolo = "RL_CC-PSP"
    case metromarePortaSanPaoloToColombo = "RL_PSP-CC"
    case viterboUrbanaFlaminioToMontebello = "RN_RMMON"
    case viterboUrbanaMontebelloToFlaminio = "RN_MONRM"
    case viterboExtraurbanaCatalanoToViterbo = "RV_CATVIT"
    case viterboExtraurbanaViterboToCatalano = "RV_VITCAT"
    /// Morlupo-Catalano: a 4th direction pair for Roma-Viterbo Extraurbana,
    /// apparently a partial/short-turn service — confirmed live via
    /// `/api/fermate/RV_MORCAT`, missing from earlier versions of this enum
    /// (built against the old cotralspa.it widget, which never listed it).
    case morlupoToCatalano = "RV_MORCAT"
    case catalanoToMorlupo = "RV_CATMOR"

    var id: String { rawValue }

    var lineName: String {
        switch self {
        case .metromareColomboToPortaSanPaolo, .metromarePortaSanPaoloToColombo:
            return "Metromare"
        case .viterboUrbanaFlaminioToMontebello, .viterboUrbanaMontebelloToFlaminio:
            return "Roma-Viterbo Urbana"
        case .viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano,
             .morlupoToCatalano, .catalanoToMorlupo:
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
        case .morlupoToCatalano: return "Morlupo → Catalano"
        case .catalanoToMorlupo: return "Catalano → Morlupo"
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
        case .morlupoToCatalano: return "Catalano"
        case .catalanoToMorlupo: return "Morlupo"
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
        case .viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano,
             .morlupoToCatalano, .catalanoToMorlupo:
            return "RVEXT"
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
        case .morlupoToCatalano: return .catalanoToMorlupo
        case .catalanoToMorlupo: return .morlupoToCatalano
        }
    }

    /// Every direction of the line that GTFS route (by its
    /// `route_short_name`) belongs to — used to go from a GTFS-derived rail
    /// `Pole` to the codes ASTRAL needs. GTFS's own rail `stop_id`/
    /// `route_id` namespacing doesn't cleanly map here: both Roma-Viterbo
    /// Urbana/Extraurbana lines share stop-id prefixes (only the route tells
    /// them apart, confirmed against the real rail `routes.txt`:
    /// `ROMALIDO`/`RVEXT`/`RVURB`), and RVEXT alone now covers two distinct
    /// direction *pairs* (the regular Catalano↔Viterbo service and the
    /// Morlupo↔Catalano short-turn) — callers shouldn't assume exactly 2
    /// results; try every candidate and keep whichever ones actually
    /// resolve a station (see `AstralTrainRepository`).
    static func directions(forGTFSRouteShortName shortName: String) -> [CotralTrainRoute]? {
        switch shortName.uppercased() {
        case "ROMALIDO": return [.metromareColomboToPortaSanPaolo, .metromarePortaSanPaoloToColombo]
        case "RVURB": return [.viterboUrbanaFlaminioToMontebello, .viterboUrbanaMontebelloToFlaminio]
        case "RVEXT": return [.viterboExtraurbanaCatalanoToViterbo, .viterboExtraurbanaViterboToCatalano, .morlupoToCatalano, .catalanoToMorlupo]
        default: return nil
        }
    }
}
