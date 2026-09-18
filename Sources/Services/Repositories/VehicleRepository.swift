import Foundation

/// Live vehicle GPS positions — always a direct Cotral call (`Automezzi.do`
/// cmd=loc). Mirrors `vehiclesService.ts.getVehicleRealTimePositions`.
@MainActor
final class VehicleRepository {
    private let client: CotralXMLClient

    init(client: CotralXMLClient = .shared) {
        self.client = client
    }

    func positions(vehicleCode: String) async throws -> [VehiclePosition] {
        let root = try await client.fetchXML(endpoint: "Automezzi.do", params: [
            "cmd": "loc",
            "userId": Config.cotralUserId,
            "pAutomezzo": vehicleCode,
            "pFormato": "xml",
        ])
        guard let root else { return [] }
        let nodes = root.children["posizione"] ?? []
        return nodes.map { node in
            VehiclePosition(
                coordX: (node.attributes["pX"] ?? "").split(separator: " ").map(String.init),
                coordY: (node.attributes["pY"] ?? "").split(separator: " ").map(String.init),
                time: node.text
            )
        }
    }
}
