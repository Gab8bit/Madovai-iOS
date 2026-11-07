import XCTest

/// Visual QA aid, not an assertion suite: opens every main screen and saves
/// a screenshot of each to /tmp/madovai-ui/tour-*.png. Skipped unless run with
///   TEST_RUNNER_MADOVAI_SCREENSHOTS=1 xcodebuild test -only-testing:CotralLiveUITests/ScreenshotTourUITests
final class ScreenshotTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MADOVAI_SCREENSHOTS"] == "1", "screenshot tour not requested")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    private func shot(_ name: String) {
        try? FileManager.default.createDirectory(atPath: "/tmp/madovai-ui", withIntermediateDirectories: true)
        let scheme = app.windows.firstMatch.exists ? (ProcessInfo.processInfo.environment["MADOVAI_SCHEME"] ?? "") : ""
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/madovai-ui/tour-\(scheme)\(name).png"))
    }

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

    private func tapMarker(_ identifier: String, avoiding blocker: String? = nil) {
        let screen = app.windows.firstMatch.frame
        let safe = CGRect(x: 40, y: screen.height * 0.28, width: screen.width - 130, height: screen.height * 0.45)
        let blockers = blocker.map(frames(of:)) ?? []
        guard let target = frames(of: identifier).first(where: { f in
            safe.contains(CGPoint(x: f.midX, y: f.midY)) && !blockers.contains { $0.insetBy(dx: -2, dy: -2).intersects(f) }
        }) else { return }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.midX, dy: target.midY)).tap()
    }

    private func closeSheet() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.53))
            .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
        sleep(1)
        if app.buttons["Reset"].exists { app.buttons["Reset"].tap() }
        sleep(1)
    }

    func testTour() {
        _ = app.descendants(matching: .any).matching(identifier: "map.vehicle").firstMatch.waitForExistence(timeout: 25)
        sleep(3)
        shot("01-map")

        tapMarker("map.vehicle")
        sleep(5)
        shot("02-vehicle-sheet")
        closeSheet()

        tapMarker("map.atacStop", avoiding: "map.vehicle")
        sleep(5)
        shot("03-atac-stop")
        closeSheet()

        tapMarker("map.pole", avoiding: "map.vehicle")
        sleep(5)
        shot("04-pole")
        closeSheet()

        let field = app.textFields["Cerca una fermata o una linea…"]
        field.tap()
        field.typeText("Acilia")
        sleep(3)
        shot("05-search")
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Cotral · treno'")).firstMatch.tap()
        sleep(5)
        shot("06-rail-station")
        closeSheet()

        app.tabBars.buttons["Linee"].tap()
        sleep(3)
        shot("07-linee")
        app.staticTexts["METROMARE"].tap()
        sleep(3)
        shot("08-linea-metromare")

        app.tabBars.buttons["Promemoria"].tap()
        app.buttons["Nuovo promemoria"].firstMatch.tap()
        sleep(1)
        shot("09-reminder-form")
    }
}
