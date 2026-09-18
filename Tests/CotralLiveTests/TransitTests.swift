import XCTest
@testable import CotralLive

final class TransitTests: XCTestCase {
    private func makeTransit(tempoTransito: String, ritardoSeconds: Int, monitorata: String = "1", isAlive: Bool? = true) -> Transit {
        Transit(
            idCorsa: "1",
            percorso: "RL_PSP-CC",
            partenzaCorsa: "",
            orarioPartenzaCorsa: tempoTransito,
            arrivoCorsa: "Cristoforo Colombo",
            orarioArrivoCorsa: "",
            soppressa: "0",
            numeroOrdine: "1",
            tempoTransito: tempoTransito,
            ritardoSeconds: ritardoSeconds,
            passato: "0",
            automezzo: Vehicle(codice: "T1", isAlive: isAlive),
            testoFermata: "",
            dataModifica: "",
            instradamento: "",
            banchina: "",
            monitorata: monitorata,
            accessibile: "0"
        )
    }

    func testAdjustedDisplayTimeAddsReliableDelay() {
        let transit = makeTransit(tempoTransito: "17:31", ritardoSeconds: 120)
        XCTAssertEqual(transit.adjustedDisplayTime, "17:33")
    }

    func testAdjustedDisplayTimeSubtractsForEarlyArrival() {
        let transit = makeTransit(tempoTransito: "17:31", ritardoSeconds: -120)
        XCTAssertEqual(transit.adjustedDisplayTime, "17:29")
    }

    func testAdjustedDisplayTimeWrapsPastMidnight() {
        let transit = makeTransit(tempoTransito: "23:55", ritardoSeconds: 10 * 60)
        XCTAssertEqual(transit.adjustedDisplayTime, "00:05")
    }

    func testAdjustedDisplayTimeWrapsBeforeMidnight() {
        let transit = makeTransit(tempoTransito: "00:05", ritardoSeconds: -10 * 60)
        XCTAssertEqual(transit.adjustedDisplayTime, "23:55")
    }

    func testAdjustedDisplayTimeIgnoresSubMinuteDelay() {
        let transit = makeTransit(tempoTransito: "17:31", ritardoSeconds: 30)
        XCTAssertEqual(transit.adjustedDisplayTime, "17:31")
    }

    func testAdjustedDisplayTimeIgnoredWhenNotRealtime() {
        // monitorata == "0" -> .scheduled tracking status -> isDelayReliable == false,
        // even though ritardoSeconds looks like a real delay (Cotral fills it with a
        // fictitious value outside the realtime state — see Transit.ritardoSeconds).
        let transit = makeTransit(tempoTransito: "17:31", ritardoSeconds: 300, monitorata: "0")
        XCTAssertEqual(transit.adjustedDisplayTime, "17:31")
    }

    func testAdjustedDisplayTimeIgnoredWhenVehicleNotAlive() {
        let transit = makeTransit(tempoTransito: "17:31", ritardoSeconds: 300, isAlive: false)
        XCTAssertEqual(transit.adjustedDisplayTime, "17:31")
    }
}
