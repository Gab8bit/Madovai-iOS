import XCTest

/// The app pointed at a server that refuses connections: every screen must
/// say so (with a retry) instead of staying blank or crashing.
final class ErrorHandlingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-MadovaiAPIBaseURL", "http://127.0.0.1:9/api/v1"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Consenti mentre usi l'app"] where springboard.buttons[label].waitForExistence(timeout: 1) {
            springboard.buttons[label].tap()
        }
    }

    func testMapShowsServerUnreachableBannerWithRetry() {
        let banner = app.staticTexts.matching(NSPredicate(format: "label == 'Server non raggiungibile' OR label == 'Errore di connessione'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "no connection error banner on the map")
        XCTAssertTrue(app.staticTexts["Connessione assente o server non raggiungibile."].exists)
        let retry = app.buttons["Riprova"].firstMatch
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "the banner must come back when the retry fails too")
    }

    func testSearchAndLinesExplainTheFailure() {
        let field = app.textFields["Cerca una fermata o una linea…"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Termini")
        XCTAssertTrue(app.staticTexts["Connessione assente o server non raggiungibile."].waitForExistence(timeout: 20))

        field.typeText("\n") // dismiss the keyboard, which covers the tab bar
        app.tabBars.buttons["Linee"].tap()
        // Inside a List row the texts are merged into one accessibility element.
        let error = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Impossibile caricare i dati'")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 20), "the Linee tab didn't explain the failure")
        XCTAssertTrue(app.buttons["Riprova"].firstMatch.exists)
    }

    func testReminderSearchShowsTheFailure() {
        app.tabBars.buttons["Promemoria"].tap()
        app.buttons["Nuovo promemoria"].firstMatch.tap()
        let field = app.textFields["Cerca una fermata…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Anagnina")
        XCTAssertTrue(app.staticTexts["Connessione assente o server non raggiungibile."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars.buttons["Salva"].isEnabled)
    }
}
