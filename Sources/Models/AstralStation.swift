import Foundation

/// One station along a Cotral rail line+direction, as ASTRAL's own
/// `/api/fermate/<percorso>` lists it — `codice` is ASTRAL's own stop code,
/// confirmed **not** the same numbering as Cotral's PIV.do pole codes
/// despite both looking like "ff900xx" (e.g. EUR Magliana is "ff90005" here,
/// "ff90007" in PIV.do, at the same moment). Matching a GTFS rail stop to
/// one of these is by name (`AstralTrainRepository`), there's no shared id.
struct AstralStation: Decodable, Identifiable, Hashable {
    let nomeFermata: String
    let codice: String
    let ordine: Int

    var id: String { codice }
}
