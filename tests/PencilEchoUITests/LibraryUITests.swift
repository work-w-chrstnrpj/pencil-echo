import XCTest

// The app isolates its test library only in Debug. Never run these destructive
// synthetic-data journeys against a Release app or its ordinary library.
#if DEBUG

@MainActor
final class LibraryUITests: XCTestCase {
    private func application(damaged: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-libraryTestRoot", UUID().uuidString]
        if damaged { app.launchArguments.append("-libraryTestDamaged") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        return app
    }

    private func card(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-document-' AND label BEGINSWITH %@", title)).firstMatch
    }

    private func closeEditor(_ app: XCUIApplication) {
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(app.navigationBars["Pencil Echo"].waitForExistence(timeout: 10))
    }

    func testCreateRenameReopenRelaunchAndConfirmedDelete() {
        let app = application()
        app.launch()
        app.buttons["New Canvas"].firstMatch.tap()
        closeEditor(app)
        let canvas = card(app, title: "Untitled Canvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.press(forDuration: 1)
        app.buttons["Rename"].firstMatch.tap()
        let field = app.textFields["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The rename sheet focuses the field with its insertion point at the end.
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText("Library journey")
        app.navigationBars["Rename"].buttons["Rename"].tap()
        let renamed = card(app, title: "Library journey")
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        closeEditor(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(card(app, title: "Library journey").waitForExistence(timeout: 10))
        app.buttons["New Notebook"].firstMatch.tap()
        closeEditor(app)
        XCTAssertTrue(card(app, title: "Untitled Notebook").waitForExistence(timeout: 5))
        card(app, title: "Library journey").press(forDuration: 1)
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(card(app, title: "Library journey").exists)
        card(app, title: "Library journey").press(forDuration: 1)
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(card(app, title: "Library journey").waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(card(app, title: "Untitled Notebook").waitForExistence(timeout: 10))
        XCTAssertFalse(card(app, title: "Library journey").exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "009-library-after-relaunch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRichSourceSaveCancelUndoAndReopen() {
        let app = application()
        app.launch()
        app.buttons["New Canvas"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Add Markdown or formula"].waitForExistence(timeout: 10))
        app.buttons["Add Markdown or formula"].tap()
        app.buttons["Markdown"].firstMatch.tap()
        let source = app.textViews["object-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        let original = source.value as? String ?? ""
        source.typeText("# Editable answer\n\n**Saved** with $x^2$ and $$\\frac{1}{2}$$\n\n")
        // Record the actual draft: a tap may position the caret anywhere in the
        // existing source. Save/reopen must preserve that exact multiline edit.
        let edited = source.value as? String ?? ""
        XCTAssertNotEqual(edited, original)
        XCTAssertTrue(edited.contains("Editable answer"))
        app.navigationBars["Edit source"].buttons["Save"].tap()
        XCTAssertTrue(source.waitForNonExistence(timeout: 5))
        app.buttons["Undo"].firstMatch.tap()
        app.otherElements.matching(NSPredicate(format: "label == %@", "Markdown: " + original)).firstMatch.doubleTap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, original)
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        app.buttons["Redo"].firstMatch.tap()
        app.otherElements.matching(NSPredicate(format: "label == %@", "Markdown: " + edited)).firstMatch.doubleTap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, edited)
        source.tap()
        source.typeText(" discarded draft")
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        closeEditor(app)
        card(app, title: "Untitled Canvas").tap()
        // Select mode is restored explicitly for the reopened document.
        app.buttons["Select ink and objects"].tap()
        let object = app.otherElements.matching(NSPredicate(format: "label == %@", "Markdown: " + edited)).firstMatch
        XCTAssertTrue(object.waitForExistence(timeout: 5))
        object.doubleTap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, edited)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "011-source-and-native-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        let canvas = app.descendants(matching: .any)["editor-canvas"].firstMatch
        for _ in 0..<3 { canvas.pinch(withScale: 4, velocity: 4) }
        XCTAssertEqual(canvas.value as? String, "400% zoom")
        let zoom = XCTAttachment(screenshot: app.screenshot())
        zoom.name = "011-canvas-4x"
        zoom.lifetime = .keepAlways
        add(zoom)
        closeEditor(app)
        app.terminate()
    }

    func testDamagedPackageAndAccessibilityTextSize() {
        let app = application(damaged: true, largeText: true)
        app.launch()
        let damaged = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-document-' AND label CONTAINS %@", "Can't open")).firstMatch
        XCTAssertTrue(damaged.waitForExistence(timeout: 10))
        XCTAssertTrue(damaged.isHittable)
        damaged.tap()
        XCTAssertTrue(app.alerts["Can't open"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(damaged.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "009-library-large-text-damaged-package"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

#endif
