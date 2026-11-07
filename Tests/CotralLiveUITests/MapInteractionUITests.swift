import XCTest

/// End-to-end checks against the live production backend: they drive the
/// real app in the simulator (location set to Roma Termini). Data is live,
/// so assertions are about behaviour (a tap opens the right sheet, vehicles
/// survive a zoom), not about specific lines or times.
final class MapInteractionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        allowSystemAlerts()
    }

    // MARK: Helpers

    private var vehicles: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "map.vehicle") }
    private var atacStops: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "map.atacStop") }
    private var poles: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "map.pole") }

    private func allowSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Consenti mentre usi l'app", "Allow", "Consenti"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) { button.tap() }
        }
    }

    private func waitForVehicles(timeout: TimeInterval = 25) {
        XCTAssertTrue(vehicles.firstMatch.waitForExistence(timeout: timeout), "no live vehicle appeared on the map")
    }

    /// Frames of every element with an identifier, from one atomic snapshot
    /// of the accessibility tree (querying hundreds of live markers one by
    /// one is slow and races with the map updating underneath).
    private func frames(of identifier: String) -> [CGRect] {
        guard let root = try? app.snapshot() else { return [] }
        var result: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.identifier == identifier { result.append(node.frame) }
            node.children.forEach(walk)
        }
        walk(root)
        return result
    }

    private func count(_ identifier: String) -> Int { frames(of: identifier).count }

    /// Taps the centre of a marker that is on screen (below the search bar,
    /// above the tab bar) and not covered by any `avoiding` marker (vehicles
    /// are drawn on top, so a covered stop would get the tap as a vehicle).
    @discardableResult
    private func tapMarker(_ identifier: String, avoiding blockerId: String? = nil) -> Bool {
        let screen = app.windows.firstMatch.frame
        let safe = CGRect(x: 40, y: screen.height * 0.28, width: screen.width - 130, height: screen.height * 0.45)
        let blockers = blockerId.map(frames(of:)) ?? []
        guard let target = frames(of: identifier).first(where: { frame in
            safe.contains(CGPoint(x: frame.midX, y: frame.midY)) && !blockers.contains { $0.insetBy(dx: -2, dy: -2).intersects(frame) }
        }) else { return false }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.midX, dy: target.midY)).tap()
        return true
    }

    private func saveScreenshot(_ name: String) {
        let directory = URL(fileURLWithPath: "/tmp/madovai-ui", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func dismissSheet() {
        let grabber = app.otherElements["Grabber"].firstMatch
        if grabber.exists {
            grabber.swipeDown(velocity: .fast)
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
        }
        sleep(1)
    }

    private func sheetText(containing text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: Tests

    /// The 1.x bug: some vehicles couldn't be tapped. Every tap, repeated on
    /// different vehicles after closing the sheet, must open a vehicle sheet
    /// and focus the map on the line.
    func testTappingVehiclesRepeatedlyAlwaysOpensTheirSheet() throws {
        waitForVehicles()
        sleep(2)
        for attempt in 0..<4 {
            guard tapMarker("map.vehicle") else { throw XCTSkip("no vehicle in a tappable area right now") }
            let sheetSubtitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tempo reale'")).firstMatch
            XCTAssertTrue(sheetSubtitle.waitForExistence(timeout: 8), "tap #\(attempt + 1) on a vehicle didn't open its sheet")
            XCTAssertTrue(app.staticTexts["Mostro solo questa linea"].waitForExistence(timeout: 5), "the map didn't focus the tapped line")
            dismissSheet()
            if sheetSubtitle.exists { dismissSheet() }
            XCTAssertTrue(sheetSubtitle.waitForNonExistence(timeout: 5), "the vehicle sheet didn't close")
            let reset = app.buttons["Reset"]
            XCTAssertTrue(reset.waitForExistence(timeout: 5))
            XCTAssertTrue(reset.isHittable, "Reset is covered")
            reset.tap()
            if !app.staticTexts["Mostro solo questa linea"].waitForNonExistence(timeout: 5) {
                saveScreenshot("reset-failed-\(attempt)")
                XCTFail("Reset didn't clear the line focus (attempt \(attempt + 1))")
            }
            sleep(1)
        }
    }

    /// The 1.x bug: live vehicles disappeared while zooming.
    func testVehiclesStayVisibleWhileZooming() {
        waitForVehicles()
        sleep(2)
        let map = app.maps.firstMatch
        XCTAssertTrue(map.exists)
        XCTAssertGreaterThan(count("map.vehicle"), 0)
        saveScreenshot("zoom-0-before")

        // Zoom in with a real pinch (fingers spreading from the centre).
        map.pinch(withScale: 2.0, velocity: 1.2)
        XCTAssertTrue(app.tabBars.buttons["Mappa"].isSelected, "the gesture left the map tab")
        let rightAfterIn = count("map.vehicle")
        saveScreenshot("zoom-1-after-in")
        sleep(3)
        saveScreenshot("zoom-2-settled-in")
        let settledIn = count("map.vehicle")
        XCTAssertGreaterThan(settledIn, 0, "vehicles vanished after zooming in")

        // Zoom back out with an animated camera move (the location button
        // re-centres at ~1.2 km), while vehicle positions keep updating.
        app.buttons["La mia posizione"].tap()
        let rightAfterOut = count("map.vehicle")
        saveScreenshot("zoom-3-after-out")
        sleep(3)
        saveScreenshot("zoom-4-settled-out")
        XCTAssertGreaterThan(count("map.vehicle"), 0, "vehicles vanished after zooming out")

        // A line fit is a much bigger animated zoom-out (whole Metro A).
        let field = app.textFields["Cerca una fermata o una linea…"]
        field.tap()
        field.typeText("Metro A")
        let result = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Metro A'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        sleep(4)
        saveScreenshot("zoom-5-line-fit")
        app.buttons["Reset"].tap()
        sleep(3)
        saveScreenshot("zoom-6-line-reset")
        XCTAssertGreaterThan(count("map.vehicle"), 0, "vehicles vanished after the wide line fit")
        print("MADOVAI-UITEST vehicles rightAfterIn=\(rightAfterIn) settledIn=\(settledIn) rightAfterOut=\(rightAfterOut)")

        // A tap still works after the zoom sequence.
        if tapMarker("map.vehicle") {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tempo reale'")).firstMatch.waitForExistence(timeout: 8))
        }
    }

    func testTappingAnAtacStopOpensItsArrivals() throws {
        XCTAssertTrue(atacStops.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        guard tapMarker("map.atacStop", avoiding: "map.vehicle") else { throw XCTSkip("every stop is covered by a vehicle right now") }
        if !app.staticTexts["Atac / Roma TPL · tempo reale"].waitForExistence(timeout: 8) {
            saveScreenshot("atac-stop-failed")
            XCTFail("tapping an Atac stop didn't open its sheet")
            return
        }
        let loaded = NSPredicate(format: "label CONTAINS 'tra ' OR label CONTAINS 'in arrivo' OR label == 'Nessun transito in tempo reale' OR label CONTAINS 'orari stimati'")
        XCTAssertTrue(app.staticTexts.matching(loaded).firstMatch.waitForExistence(timeout: 15), "the stop sheet never showed arrivals or an empty state")
    }

    func testPoleSheetAndFavoritesRoundTrip() throws {
        XCTAssertTrue(poles.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        if !tapMarker("map.pole", avoiding: "map.vehicle") {
            // No pole free of vehicles on screen right now: open one from
            // search instead, so the sheet + favorites path always runs.
            let field = app.textFields["Cerca una fermata o una linea…"]
            field.tap()
            field.typeText("Cinquecento") // matches no line, so the stop is the first row
            let result = app.buttons.matching(identifier: "search.stop.cotralBus").firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10), "no Cotral bus stop found for 'Cinquecento'")
            result.tap()
        }
        let add = app.buttons["Aggiungi ai preferiti"]
        let remove = app.buttons["Rimuovi dai preferiti"]
        if !(add.waitForExistence(timeout: 8) || remove.exists) {
            saveScreenshot("pole-failed")
            XCTFail("tapping a pole didn't open its sheet")
            return
        }
        let loaded = NSPredicate(format: "label CONTAINS 'Real-time' OR label CONTAINS 'Schedulata' OR label CONTAINS 'Tracciata' OR label == 'Nessun transito disponibile' OR label == 'Impossibile caricare i dati'")
        XCTAssertTrue(app.staticTexts.matching(loaded).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Impossibile caricare i dati"].exists, "the pole sheet failed to load")

        if add.exists { add.tap() }
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        dismissSheet()

        app.tabBars.buttons["Preferiti"].tap()
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Rimuovi"].tap()
        XCTAssertTrue(app.staticTexts["Nessun preferito"].waitForExistence(timeout: 5))
    }

    func testSearchingARailStationShowsItsTimetable() {
        let field = app.textFields["Cerca una fermata o una linea…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Acilia")
        let result = app.buttons.matching(identifier: "search.stop.cotralRail").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "no rail result for 'Acilia'")
        result.tap()
        let loaded = NSPredicate(format: "label == 'Prossimo treno' OR label == 'Corse terminate per oggi' OR label BEGINSWITH 'Verso' OR label CONTAINS 'Orario stimato'")
        let timetable = app.staticTexts.matching(loaded).firstMatch
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(timetable.waitForExistence(timeout: 15) || picker.waitForExistence(timeout: 1), "the station timetable never loaded")
    }

    func testSearchingAnAtacLineFocusesIt() {
        let field = app.textFields["Cerca una fermata o una linea…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Metro A")
        let result = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Metro A'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        XCTAssertTrue(app.staticTexts["Mostro solo questa linea"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Metro A"].waitForExistence(timeout: 5))
        app.buttons["Reset"].tap()
    }

    func testLineeTabLoadsLinesAndDetail() {
        app.tabBars.buttons["Linee"].tap()
        let metro = app.staticTexts["Metro A"]
        XCTAssertTrue(metro.waitForExistence(timeout: 15), "the line list didn't load")
        metro.tap()
        let stops = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'FERMATE (' OR label BEGINSWITH 'Fermate ('")).firstMatch
        XCTAssertTrue(stops.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Anagnina"].waitForExistence(timeout: 15))
        // Stations follow the line (backend `line` returns route order since
        // Nov 2026), not the alphabet: Anagnina, Cinecittà, Subaugusta…
        let first = app.staticTexts["Anagnina"].frame.minY
        let second = app.staticTexts["Cinecitta'"].frame.minY
        let third = app.staticTexts["Subaugusta"].frame.minY
        XCTAssertTrue(app.staticTexts["Cinecitta'"].exists && app.staticTexts["Subaugusta"].exists)
        XCTAssertLessThan(first, second, "stations aren't in line order")
        XCTAssertLessThan(second, third, "stations aren't in line order")
    }

    func testCreatingAndDeletingAReminder() {
        app.tabBars.buttons["Promemoria"].tap()
        app.buttons["Nuovo promemoria"].firstMatch.tap()
        let field = app.textFields["Cerca una fermata…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Anagnina")
        let result = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Anagnina'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        app.navigationBars.buttons["Salva"].tap()
        allowSystemAlerts()
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] 'Anagnina'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Elimina"].tap()
        XCTAssertTrue(app.staticTexts["Nessun promemoria"].waitForExistence(timeout: 5))
    }
}
