import CoreLocation

/// A "palina" (bus/train stop pole), as returned by the various /poles/* endpoints.
/// Nearly every field is optional server-side depending on which source
/// (GTFS vs live Cotral API) produced it, so this mirrors that looseness.
struct Pole: Codable, Identifiable, Hashable {
    var codicePalina: String?
    var codiceStop: String?
    var nomePalina: String?
    var nomeStop: String?
    var localita: String?
    var comune: String?
    /// Latitude.
    var coordX: Double?
    /// Longitude.
    var coordY: Double?
    var zonaTariffaria: String?
    var distanza: String?
    var destinazioni: [String]?
    var isCotral: Int?
    var isCapolinea: Int?
    var isBanchinato: Int?
    var preferita: Bool?
    /// Not part of Cotral's own field set — set locally from which GTFS
    /// feed (bus vs rail) this pole's stop came from, purely for display.
    var isTreno: Bool = false

    enum CodingKeys: String, CodingKey {
        case codicePalina, codiceStop, nomePalina, nomeStop, localita, comune
        case coordX, coordY, zonaTariffaria, distanza, destinazioni
        case isCotral, isCapolinea, isBanchinato, preferita, isTreno
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codicePalina = try c.decodeIfPresent(String.self, forKey: .codicePalina)
        // codiceStop is `string | number` server-side (GTFS sets a string,
        // the live-API path can leave a numeric stop code) — accept either.
        if let stringValue = try? c.decodeIfPresent(String.self, forKey: .codiceStop) {
            codiceStop = stringValue
        } else if let intValue = try? c.decodeIfPresent(Int.self, forKey: .codiceStop) {
            codiceStop = String(intValue)
        } else {
            codiceStop = nil
        }
        nomePalina = try c.decodeIfPresent(String.self, forKey: .nomePalina)
        nomeStop = try c.decodeIfPresent(String.self, forKey: .nomeStop)
        localita = try c.decodeIfPresent(String.self, forKey: .localita)
        comune = try c.decodeIfPresent(String.self, forKey: .comune)
        coordX = try c.decodeIfPresent(Double.self, forKey: .coordX)
        coordY = try c.decodeIfPresent(Double.self, forKey: .coordY)
        zonaTariffaria = try c.decodeIfPresent(String.self, forKey: .zonaTariffaria)
        distanza = try c.decodeIfPresent(String.self, forKey: .distanza)
        destinazioni = try c.decodeIfPresent([String].self, forKey: .destinazioni)
        isCotral = try c.decodeIfPresent(Int.self, forKey: .isCotral)
        isCapolinea = try c.decodeIfPresent(Int.self, forKey: .isCapolinea)
        isBanchinato = try c.decodeIfPresent(Int.self, forKey: .isBanchinato)
        preferita = try c.decodeIfPresent(Bool.self, forKey: .preferita)
        isTreno = try c.decodeIfPresent(Bool.self, forKey: .isTreno) ?? false
    }

    init(
        codicePalina: String? = nil, codiceStop: String? = nil,
        nomePalina: String? = nil, nomeStop: String? = nil,
        localita: String? = nil, comune: String? = nil,
        coordX: Double? = nil, coordY: Double? = nil,
        zonaTariffaria: String? = nil, distanza: String? = nil,
        destinazioni: [String]? = nil, isCotral: Int? = nil,
        isCapolinea: Int? = nil, isBanchinato: Int? = nil, preferita: Bool? = nil,
        isTreno: Bool = false
    ) {
        self.codicePalina = codicePalina
        self.codiceStop = codiceStop
        self.nomePalina = nomePalina
        self.nomeStop = nomeStop
        self.localita = localita
        self.comune = comune
        self.coordX = coordX
        self.coordY = coordY
        self.zonaTariffaria = zonaTariffaria
        self.distanza = distanza
        self.destinazioni = destinazioni
        self.isCotral = isCotral
        self.isCapolinea = isCapolinea
        self.isBanchinato = isBanchinato
        self.preferita = preferita
        self.isTreno = isTreno
    }

    /// Stable identity for a pole across responses. Falls back to
    /// codiceStop, then coordinates, so poles missing codicePalina
    /// (rare, but possible on some GTFS/live-API paths) still work in lists.
    var id: String {
        codicePalina ?? codiceStop ?? "\(coordX ?? 0),\(coordY ?? 0)"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = coordX, let lon = coordY, !(lat == 0 && lon == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayName: String {
        nomePalina ?? nomeStop ?? localita ?? "Palina \(codicePalina ?? codiceStop ?? "")"
    }

    var subtitle: String? {
        [comune, localita].compactMap { $0 }.first(where: { !$0.isEmpty })
    }
}
