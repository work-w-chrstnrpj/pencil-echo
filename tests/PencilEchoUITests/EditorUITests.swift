import XCTest

// Ticket 024: editor journeys against the single navigation bar, menus, selection bar,
// inspectors and drafts bar. Isolated Debug library only (see LibraryUITests).
#if DEBUG

@MainActor
final class EditorUITests: XCTestCase {
    private func application(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-libraryTestRoot", UUID().uuidString] + extra
        return app
    }

    private func card(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-document-' AND label BEGINSWITH %@", title)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func openNewCanvas(_ app: XCUIApplication) {
        // Ticket 025: New is a menu whose primary action creates a canvas.
        app.buttons["library-new"].firstMatch.tap()
        XCTAssertTrue(element(app, "editor-ask").waitForExistence(timeout: 10))
    }

    private func closeEditor(_ app: XCUIApplication) {
        let back = app.buttons["Done"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(app.navigationBars["Pencil Echo"].waitForExistence(timeout: 10))
    }

    private func insert(_ app: XCUIApplication, _ item: String) {
        element(app, "editor-insert-menu").tap()
        let button = app.buttons[item].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    /// Taps an empty spot near the top of the page to close a menu that's still open.
    private func closeMenu(_ app: XCUIApplication, ifShowing item: XCUIElement) {
        if item.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        _ = item.waitForNonExistence(timeout: 3)
    }

    /// The document title opens the title menu (Rename, Export, New).
    private func openTitleMenu(_ app: XCUIApplication, _ title: String) {
        let button = app.navigationBars.buttons[title].firstMatch
        if button.waitForExistence(timeout: 3) { button.tap() } else { app.navigationBars.staticTexts[title].firstMatch.tap() }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// One command row: none of the removed controls exist.
    func testOneCommandBarWithoutDuplicates() {
        let app = application()
        app.launch()
        openNewCanvas(app)
        // Undo and Redo stay in Apple's tool picker; the navigation bar has none.
        let navigation = app.navigationBars.firstMatch
        XCTAssertFalse(navigation.buttons["Undo"].exists || navigation.buttons["Redo"].exists)
        for removed in ["Toggle grid", "Pause delay", "Move toolbar to bottom", "Hand mode", "Add Markdown or formula", "Select ink and objects"] {
            XCTAssertFalse(app.buttons[removed].exists, "\(removed) should be gone")
        }
        for present in ["editor-select", "editor-insert-menu", "editor-view-menu", "editor-ask", "editor-answer-menu", "editor-chat", "editor-claude-code", "editor-settings"] {
            XCTAssertTrue(element(app, present).exists, "\(present) missing")
        }
        attach(app, "024-editor-regular")
        closeEditor(app)
    }

    func testRichSourceSaveCancelUndoAndReopen() {
        let app = application()
        app.launch()
        openNewCanvas(app)
        insert(app, "Markdown")
        let source = app.textViews["object-source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        let original = source.value as? String ?? ""
        source.typeText("# Editable answer\n\n**Saved** with $x^2$ and $$\\frac{1}{2}$$\n\n")
        let edited = source.value as? String ?? ""
        XCTAssertNotEqual(edited, original)
        XCTAssertTrue(edited.contains("Editable answer"))
        app.navigationBars["Edit source"].buttons["Save"].tap()
        XCTAssertTrue(source.waitForNonExistence(timeout: 5))
        // Undo and redo live in the tool picker and on the keyboard now.
        app.typeKey("z", modifierFlags: .command)
        app.otherElements.matching(NSPredicate(format: "label == %@", "Markdown: " + original)).firstMatch.doubleTap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, original)
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        app.typeKey("z", modifierFlags: [.command, .shift])
        app.otherElements.matching(NSPredicate(format: "label == %@", "Markdown: " + edited)).firstMatch.doubleTap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, edited)
        source.tap()
        source.typeText(" discarded draft")
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        closeEditor(app)
        card(app, title: "Untitled Canvas").tap()
        element(app, "editor-select").tap()
        let object = app.otherElements.matching(NSPredicate(format: "label == %@", "Markdown: " + edited)).firstMatch
        XCTAssertTrue(object.waitForExistence(timeout: 5))
        object.doubleTap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.value as? String, edited)
        attach(app, "011-source-and-native-preview")
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        let canvas = element(app, "editor-canvas")
        for _ in 0..<3 { canvas.pinch(withScale: 4, velocity: 4) }
        XCTAssertEqual(canvas.value as? String, "400% zoom")
        closeEditor(app)
        app.terminate()
    }

    /// Insert a text object, select it, and delete it from the floating selection bar.
    func testSelectionBarEditAndDelete() {
        let app = application()
        app.launch()
        openNewCanvas(app)
        insert(app, "Text")
        XCTAssertTrue(app.navigationBars["Edit source"].waitForExistence(timeout: 5))
        app.navigationBars["Edit source"].buttons["Save"].tap()
        // Adding an object selects it, so the bar shows Edit, Ask AI and Delete.
        let delete = element(app, "selection-delete")
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "selection-edit").exists && element(app, "selection-ask").exists)
        attach(app, "024-selection-bar")
        element(app, "selection-edit").tap()
        XCTAssertTrue(app.navigationBars["Edit source"].waitForExistence(timeout: 5))
        app.navigationBars["Edit source"].buttons["Cancel"].tap()
        delete.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Text")).firstMatch.exists)
        closeEditor(app)
    }

    func testEditorShellControls() {
        let app = application()
        app.launch()
        openNewCanvas(app)
        // Answer mode: flip automatic answers (the setting persists between runs, so
        // compare against the starting state) and flip it back at the end.
        let startedAuto = element(app, "editor-answer-menu").label.contains("automatic")
        let flipped = startedAuto ? "only when you ask" : "automatic"
        element(app, "editor-answer-menu").tap()
        let auto = app.buttons["Answer automatically when I pause"].firstMatch
        XCTAssertTrue(auto.waitForExistence(timeout: 5))
        auto.tap()
        // Toggles keep a menu open on iPadOS; close it before reading the bar.
        closeMenu(app, ifShowing: auto)
        XCTAssertTrue(element(app, "editor-answer-menu").label.contains(flipped))
        // Rename from the title menu.
        openTitleMenu(app, "Untitled Canvas")
        // Menu items are system menu items without SwiftUI identifiers, so find it by label.
        let rename = app.buttons["Rename…"].firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count) + "Shell journey")
        app.alerts.buttons["Rename"].tap()
        // View menu: page pattern off, then full screen and back.
        element(app, "editor-view-menu").tap()
        app.buttons["Show page pattern"].firstMatch.tap()
        let fullScreen = app.buttons["Full screen"].firstMatch
        if !fullScreen.exists { element(app, "editor-view-menu").tap() }
        XCTAssertTrue(fullScreen.waitForExistence(timeout: 5))
        fullScreen.tap()
        let exit = element(app, "editor-exit-fullscreen")
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "editor-ask").isHittable)
        attach(app, "024-fullscreen")
        exit.tap()
        XCTAssertTrue(element(app, "editor-ask").waitForExistence(timeout: 5))
        // Settings opens as an inspector and closes with the same button.
        element(app, "editor-settings").tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Settings'")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "024-settings-inspector")
        // With the panel open, the narrow bar keeps Settings in its overflow; close with Done.
        app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Settings'")).firstMatch.buttons["Done"].firstMatch.tap()
        closeEditor(app)
        XCTAssertTrue(card(app, title: "Shell journey").waitForExistence(timeout: 5))
        card(app, title: "Shell journey").tap()
        XCTAssertTrue(element(app, "editor-answer-menu").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "editor-answer-menu").label.contains(flipped))
        // Restore the starting state for later runs.
        element(app, "editor-answer-menu").tap()
        let restore = app.buttons["Answer automatically when I pause"].firstMatch
        restore.tap()
        closeMenu(app, ifShowing: restore)
        closeEditor(app)
    }

    func testChatFixtureAcceptReopenAndClear() {
        let app = application(["-chatFixture"])
        app.launch()
        openNewCanvas(app)
        element(app, "editor-chat").tap()
        let input = element(app, "chat-input")
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Solve the time of descent")
        app.buttons["Send"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Accept all"].firstMatch.waitForExistence(timeout: 15))
        attach(app, "021-chat-drafts")
        // Close chat (with the inspector open, a narrow bar moves Chat into its overflow menu).
        app.buttons["Close"].firstMatch.tap()
        let accept = element(app, "drafts-accept")
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        attach(app, "024-drafts-bar")
        accept.tap()
        XCTAssertTrue(accept.waitForNonExistence(timeout: 5))
        element(app, "editor-chat").tap()
        closeEditor(app)
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForExistence(timeout: 5))
        card(app, title: "Untitled Canvas").tap()
        // The chat inspector reopens with the document.
        // Chat bubbles are single accessibility elements labeled "You: …" (ticket 026).
        let sent = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Solve the time of descent")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        app.buttons["New chat"].tap()
        XCTAssertTrue(sent.waitForNonExistence(timeout: 5))
        app.buttons["Close"].tap()
        closeEditor(app)
    }

    func testCompactSettingsSheet() {
        let app = application(["-editorCompactWidth"])
        app.launch()
        app.buttons["library-new"].firstMatch.tap()
        let settings = element(app, "editor-settings")
        if !settings.waitForExistence(timeout: 10) {
            // Compact width may move Settings into the bar's overflow menu.
            app.buttons["More"].firstMatch.tap()
        }
        // The library's sidebar row is also named "Settings", so use the identifier.
        settings.tap()
        let sheet = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Settings'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        attach(app, "024-compact-settings-sheet")
        sheet.buttons["Done"].firstMatch.tap()
        closeEditor(app)
    }
}

#endif
