import Foundation

/// Live transits for a pole — always a direct Cotral call (`PIV.do` cmd=1),
/// since GTFS is static data and can't answer this. Mirrors
/// `transitsService.ts.getTransitsByPoleCode` field-for-field, including
/// the seconds→"HH:MM" conversion and lat/lon normalization that server
/// used to do before handing JSON to a client.
@MainActor
final class TransitsRepository {
    struct Result {
        var pole: Pole
        var transits: [Transit]
    }

    private let client: CotralXMLClient

    init(client: CotralXMLClient = .shared) {
        self.client = client
    }

    func transits(poleCode: String) async throws -> Result? {
        let root = try await client.fetchXML(endpoint: "PIV.do", params: [
            "cmd": "1",
            "userId": Config.cotralUserId,
            "pCodice": poleCode,
            "pFormato": "xml",
            "pDelta": Config.cotralDelta,
        ])

        guard let root, let poleNode = root.firstChild("palina") else { return nil }
        let corsaNodes = root.children["corsa"] ?? []
        guard !corsaNodes.isEmpty else { return nil }

        let rawLat = Double(poleNode.childText("latitudine")) ?? 0
        let rawLon = Double(poleNode.childText("longitudine")) ?? 0
        let normalized = CotralTimeUtils.normalizeLatLon(rawLat, rawLon)

        let pole = Pole(
            codicePalina: poleNode.childText("codice"),
            nomePalina: poleNode.childText("nomePalina"),
            nomeStop: poleNode.childText("nomeStop"),
            localita: poleNode.childText("localita"),
            comune: poleNode.childText("comune"),
            coordX: normalized.lat,
            coordY: normalized.lon,
            preferita: poleNode.childText("preferita") == "1"
        )

        return Result(pole: pole, transits: corsaNodes.map(makeTransit))
    }

    private func makeTransit(_ node: XMLNode) -> Transit {
        let automezzoNode = node.firstChild("automezzo")
        let vehicleCode = automezzoNode?.text.trimmingCharacters(in: .whitespaces)

        return Transit(
            idCorsa: node.childText("idCorsa"),
            percorso: node.childText("percorso"),
            partenzaCorsa: node.childText("partenzaCorsa"),
            orarioPartenzaCorsa: CotralTimeUtils.readableTime(fromSeconds: node.childText("orarioPartenzaCorsa")),
            arrivoCorsa: node.childText("arrivoCorsa"),
            orarioArrivoCorsa: CotralTimeUtils.readableTime(fromSeconds: node.childText("orarioArrivoCorsa")),
            soppressa: node.childText("soppressa"),
            numeroOrdine: node.childText("numeroOrdine"),
            tempoTransito: CotralTimeUtils.readableTime(fromSeconds: node.childText("tempoTransito")),
            ritardoSeconds: Int(node.childText("ritardo").trimmingCharacters(in: .whitespaces)) ?? 0,
            passato: node.childText("passato"),
            automezzo: Vehicle(
                codice: (vehicleCode?.isEmpty ?? true) ? nil : vehicleCode,
                isAlive: automezzoNode?.attributes["isAlive"] == "1"
            ),
            testoFermata: node.childText("testoFermata"),
            dataModifica: node.childText("dataModifica"),
            instradamento: node.childText("instradamento"),
            banchina: node.childText("banchina"),
            monitorata: node.childText("monitorata"),
            accessibile: node.childText("accessibile")
        )
    }
}
