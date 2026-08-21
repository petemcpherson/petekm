//
//  PeteKMUITests.swift
//  PeteKMUITests
//
//  The capture loop (spec §4.1, §8): summon, type, hide, come back to the same
//  file. The *global* shortcut half of that loop needs Accessibility
//  permission, which a test runner can't grant itself — these tests drive the
//  same window lifecycle through activation and ⌘W instead.
//

import XCTest

final class PeteKMUITests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = URL.temporaryDirectory.appending(path: "petekm-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PETEKM_UITEST_FOLDER"] = folder.path(percentEncoded: false)
        app.launch()
        return app
    }

    @MainActor
    func testTypingIsSavedToTodaysDailySticky() throws {
        let app = launchedApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let text = "certificate auth notes \(UUID().uuidString.prefix(8))"
        app.typeText(text)

        let daily = folder.appending(path: "daily/\(Self.todayFilename()).md")
        let saved = expectation(description: "autosaved")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if let contents = try? String(contentsOf: daily, encoding: .utf8), contents.contains(text) {
                timer.invalidate()
                saved.fulfill()
            }
        }
        wait(for: [saved], timeout: 20)
        poll.invalidate()
    }

    @MainActor
    func testClosingTheWindowHidesTheAppWithoutQuitting() throws {
        let app = launchedApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        app.typeKey("w", modifierFlags: .command)   // §8.7: ⌘W hides, never quits

        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.state == .runningForeground)
        XCTAssertNotEqual(app.state, .notRunning)

        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    private static func todayFilename() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
