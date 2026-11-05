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

    // Ticket 025 helpers are used only by the three library journeys.
    private func libraryCreate(_ app: XCUIApplication, notebook: Bool = false) {
        let new = app.buttons["library-new"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        if notebook {
            new.press(forDuration: 1)
            app.buttons["New Notebook"].firstMatch.tap()
        } else { new.tap() }
    }

    /// Switches grid ↔ list through View options. Menu items are system menu items,
    /// which don't carry SwiftUI identifiers, so they're found by label.
    private func libraryToggleLayout(_ app: XCUIApplication) {
        let showingList = app.descendants(matching: .any)["library-list"].firstMatch.exists
        let target = app.buttons[showingList ? "Grid" : "List"].firstMatch
        if !target.exists { app.buttons["library-sort"].tap() }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
    }

    private func libraryCapture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "025-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCreateRenameReopenRelaunchAndConfirmedDelete() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = application()
        app.launchArguments += ["-spike004", "-provider007"]
        app.launch()
        XCTAssertFalse(app.buttons["Debug"].exists)
        libraryCreate(app)
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
        libraryCreate(app, notebook: true)
        closeEditor(app)
        XCTAssertTrue(card(app, title: "Untitled Notebook").waitForExistence(timeout: 5))
        libraryCapture(app, "grid")
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

    func testFavoriteSearchAndListLayoutSurviveRelaunch() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = application()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        app.launch()
        app.descendants(matching: .any)["library-sidebar-favorites"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Favorites Yet"].waitForExistence(timeout: 5))
        libraryCapture(app, "empty-favorites")
        app.descendants(matching: .any)["library-sidebar-all"].firstMatch.tap()
        libraryCreate(app)
        closeEditor(app)

        let canvas = card(app, title: "Untitled Canvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // Normalize the layout remembered from any earlier run.
        if app.descendants(matching: .any)["library-list"].firstMatch.exists {
            libraryToggleLayout(app)
        }
        XCTAssertTrue(app.descendants(matching: .any)["library-grid"].firstMatch.waitForExistence(timeout: 5))
        canvas.press(forDuration: 1)
        app.buttons["Add to Favorites"].firstMatch.tap()

        let favorites = app.descendants(matching: .any)["library-sidebar-favorites"].firstMatch
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForExistence(timeout: 5))
        let starred = XCTAttachment(screenshot: app.screenshot())
        starred.name = "022-library-favorites"
        starred.lifetime = .keepAlways
        add(starred)

        // Sort and layout first: while search is active, iPadOS hides the toolbar's View options.
        app.buttons["library-sort"].tap()
        app.buttons["Title"].firstMatch.tap()
        libraryToggleLayout(app)
        XCTAssertTrue(app.descendants(matching: .any)["library-list"].firstMatch.waitForExistence(timeout: 5))

        // Search filters the selected section as the query is typed.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Untitled")
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForExistence(timeout: 5))
        search.typeText(" missing")
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForNonExistence(timeout: 5))
        // iPadOS shows "No Results for “…”".
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No Results")).firstMatch.waitForExistence(timeout: 5))
        libraryCapture(app, "search-no-results")
        let typed = search.value as? String ?? ""
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForExistence(timeout: 5))
        // The list layout chosen before searching is still shown.
        let list = app.descendants(matching: .any)["library-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(card(app, title: "Untitled Canvas").exists)
        libraryCapture(app, "list")
        let listed = XCTAttachment(screenshot: app.screenshot())
        listed.name = "022-library-list"
        listed.lifetime = .keepAlways
        add(listed)

        // Relaunch: the list layout and the favorite survive.
        app.terminate()
        app.launch()
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["library-list"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["library-sidebar-favorites"].firstMatch.tap()
        XCTAssertTrue(card(app, title: "Untitled Canvas").waitForExistence(timeout: 5))
        let afterRelaunch = XCTAttachment(screenshot: app.screenshot())
        afterRelaunch.name = "022-library-list-after-relaunch"
        afterRelaunch.lifetime = .keepAlways
        add(afterRelaunch)
        libraryCapture(app, "dark-mode")
        app.buttons["library-sort"].tap()
        XCTAssertTrue(app.buttons["Title"].firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        app.buttons["library-ai-settings"].tap()
        XCTAssertTrue(app.navigationBars["AI Settings"].waitForExistence(timeout: 5))
        app.navigationBars["AI Settings"].buttons["Done"].tap()
        card(app, title: "Untitled Canvas").swipeLeft()
        app.buttons["Unfavorite"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Favorites Yet"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["library-sidebar-all"].firstMatch.tap()
        card(app, title: "Untitled Canvas").swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(card(app, title: "Untitled Canvas").exists)
    }

    func testDamagedPackageAndAccessibilityTextSize() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
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
        libraryCapture(app, "large-text-damaged")
    }
}

#endif
