import XCTest
@testable import CotralLive

/// The 3 per-source adapters that normalize a Promemoria's live check into
/// one `ReminderDepartureStatus` — including the "prossimo utile" fallback
/// time used in the notification body when the very next departure turns
/// out to be cancelled, and the two-signal Atac cancellation check
/// (trip-level CANCELED/DELETED vs. stop-level SKIPPED, see
/// `AtacStopArrivalClient`'s doc comment).
final class ReminderDepartureStatusTests: XCTestCase {
    // MARK: - Cotral bus (Transit)

    private func makeTransit(minutesFromNow: Int, ritardoSeconds: Int = 0, soppressa: String = "N", monitorata: String = "1", isAlive: Bool? = true) -> Transit {
        let target = Calendar.current.date(byAdding: .minute, value: minutesFromNow, to: Date())!
        let comps = Calendar.current.dateComponents([.hour, .minute], from: target)
        let time = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        return Transit(
            idCorsa: UUID().uuidString,
            percorso: "017",
            partenzaCorsa: "",
            orarioPartenzaCorsa: time,
            arrivoCorsa: "",
            orarioArrivoCorsa: "",
            soppressa: soppressa,
            numeroOrdine: "1",
            tempoTransito: time,
            ritardoSeconds: ritardoSeconds,
            passato: "0",
            automezzo: Vehicle(codice: "B1", isAlive: isAlive),
            testoFermata: "",
            dataModifica: "",
            instradamento: "",
            banchina: "",
            monitorata: monitorata,
            accessibile: "0"
        )
    }

    func testCotralBusPicksSoonestNotYetPassed() {
        let transits = [makeTransit(minutesFromNow: 20), makeTransit(minutesFromNow: 5), makeTransit(minutesFromNow: -3)]
        let status = ReminderDepartureStatus.nextUpcoming(from: transits)
        XCTAssertNotNil(status)
        XCTAssertFalse(status!.isCancelled)
    }

    func testCotralBusReadsSoppressaYAsCancelled() {
        let transits = [makeTransit(minutesFromNow: 5, soppressa: "Y")]
        XCTAssertEqual(ReminderDepartureStatus.nextUpcoming(from: transits)?.isCancelled, true)
    }

    func testCotralBusCancelledFallsBackToNextUsefulTime() {
        let transits = [makeTransit(minutesFromNow: 5, soppressa: "Y"), makeTransit(minutesFromNow: 15, soppressa: "N")]
        let status = ReminderDepartureStatus.nextUpcoming(from: transits)
        XCTAssertEqual(status?.isCancelled, true)
        XCTAssertNotNil(status?.nextUsefulTime)
    }

    func testCotralBusNilWhenNoUpcomingRuns() {
        let transits = [makeTransit(minutesFromNow: -10)]
        XCTAssertNil(ReminderDepartureStatus.nextUpcoming(from: transits))
    }

    func testCotralBusDelayUnreliableWhenNotRealtime() {
        let transits = [makeTransit(minutesFromNow: 5, ritardoSeconds: 300, monitorata: "0")]
        XCTAssertNil(ReminderDepartureStatus.nextUpcoming(from: transits)?.delayMinutes)
    }

    // MARK: - Cotral rail (AstralDeparture)

    private func makeDeparture(time: String, delayMinutes: Int?, isCancelled: Bool = false) -> AstralDeparture {
        AstralDeparture(id: time, time: time, sortSeconds: 0, delayMinutes: delayMinutes, isCancelled: isCancelled, isReplacementBus: false)
    }

    func testCotralRailMapsFieldsDirectly() {
        let status = ReminderDepartureStatus.nextUpcoming(from: [makeDeparture(time: "18:11", delayMinutes: 4)])
        XCTAssertEqual(status?.time, "18:11")
        XCTAssertEqual(status?.delayMinutes, 4)
        XCTAssertEqual(status?.isCancelled, false)
    }

    func testCotralRailCancelledFallsBackToNextUsefulTime() {
        let entries = [makeDeparture(time: "18:11", delayMinutes: nil, isCancelled: true), makeDeparture(time: "18:31", delayMinutes: 0)]
        let status = ReminderDepartureStatus.nextUpcoming(from: entries)
        XCTAssertEqual(status?.isCancelled, true)
        XCTAssertEqual(status?.nextUsefulTime, "18:31")
    }

    func testCotralRailNilWhenNoEntries() {
        XCTAssertNil(ReminderDepartureStatus.nextUpcoming(from: [AstralDeparture]()))
    }

    // MARK: - Atac bus/tram (AtacStopArrival)

    func testAtacMapsDelaySecondsToMinutes() {
        let arrival = AtacStopArrival(time: Date(), delaySeconds: 185, isCancelled: false)
        XCTAssertEqual(ReminderDepartureStatus.nextUpcoming(from: [arrival])?.delayMinutes, 3)
    }

    func testAtacCancelledFallsBackToNextUsefulTime() {
        let arrivals = [
            AtacStopArrival(time: Date(), delaySeconds: nil, isCancelled: true),
            AtacStopArrival(time: Date().addingTimeInterval(600), delaySeconds: nil, isCancelled: false),
        ]
        let status = ReminderDepartureStatus.nextUpcoming(from: arrivals)
        XCTAssertEqual(status?.isCancelled, true)
        XCTAssertNotNil(status?.nextUsefulTime)
    }

    func testAtacNoNextUsefulTimeWhenOnlyEntryIsCancelled() {
        let status = ReminderDepartureStatus.nextUpcoming(from: [AtacStopArrival(time: Date(), delaySeconds: nil, isCancelled: true)])
        XCTAssertEqual(status?.isCancelled, true)
        XCTAssertNil(status?.nextUsefulTime)
    }
}
