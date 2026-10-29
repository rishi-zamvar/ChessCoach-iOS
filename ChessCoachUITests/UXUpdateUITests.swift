import XCTest

/// 0.9 "Coach, not quiz": the new flows end to end — feedback from any screen, Coach-mode puzzles,
/// the analysis board, and the plan never dead-ending. Screenshots are attached to the results.
final class UXUpdateUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  func test_givenToday_whenFeedbackOpened_thenSheetCarriesScreenAndSends() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    XCTAssertTrue(app.buttons["plan-start"].waitForExistence(timeout: 15))
    shot(app, "u01-today")
    app.buttons["open-feedback"].firstMatch.tap()
    XCTAssertTrue(app.textViews["feedback-text"].waitForExistence(timeout: 5) || app.textFields["feedback-text"].waitForExistence(timeout: 2))
    app.buttons["feedback-cat-bug"].tap()
    app.typeText("Cannot progress beyond this page.")
    shot(app, "u02-feedback-sheet")
    app.buttons["feedback-send"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["feedback-sent"].waitForExistence(timeout: 5))
    shot(app, "u03-feedback-sent")
    app.buttons["feedback-cancel"].tap()
  }

  func test_givenCoachMode_whenSkillPuzzleOpened_thenPlaysOutWithCoachChip() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting", "-coachMode"]
    app.launch()
    app.tabBars.buttons["Train"].tap()
    XCTAssertTrue(app.buttons["train-plan-link"].waitForExistence(timeout: 10))
    shot(app, "u04-train")
    app.buttons["skill-B1"].tap()
    XCTAssertTrue(app.staticTexts["coach-mode-chip"].waitForExistence(timeout: 10))
    sleep(2)
    shot(app, "u05-coach-puzzle")
    app.buttons["runner-close"].tap()
  }

  func test_givenAnalyzeTab_whenAnalysisBoardOpened_thenMovesAndEngineLines() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    app.tabBars.buttons["Analyze"].tap()
    let open = app.buttons["open-analysis-board"]
    XCTAssertTrue(open.waitForExistence(timeout: 10))
    open.tap()
    app.buttons["paste-open"].tap()
    XCTAssertTrue(app.buttons["analysis-close"].waitForExistence(timeout: 10))
    let board = app.descendants(matching: .any)["board"]
    XCTAssertTrue(board.waitForExistence(timeout: 5))
    // e2-e4 by tapping squares (White at the bottom): e2 is column 4, row 6.
    let frame = board.frame
    let sq = frame.width / 8
    func tapSquare(_ col: Int, _ row: Int) {
      board.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: sq * (CGFloat(col) + 0.5), dy: sq * (CGFloat(row) + 0.5))).tap()
    }
    tapSquare(4, 6)
    tapSquare(4, 4)
    XCTAssertTrue(app.staticTexts["analysis-explain"].waitForExistence(timeout: 5))
    sleep(3)
    shot(app, "u06-analysis-board")
    app.buttons["analysis-close"].tap()
  }

  func test_givenSettings_whenOpened_thenPrivacyAndPuzzleModeControls() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    app.buttons["open-settings"].tap()
    // Form pickers don't carry identifiers; find them by their label. Rows off screen don't exist yet.
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    let mode = app.staticTexts["Puzzle feedback"]
    for _ in 0..<5 where !mode.exists { app.swipeUp() }
    XCTAssertTrue(mode.exists)
    let analytics = app.switches["settings-analytics"]
    for _ in 0..<4 where !analytics.exists { app.swipeUp() }
    XCTAssertTrue(analytics.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["settings-delete-data"].exists)
    shot(app, "u07-settings")
  }

  private func shot(_ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
    let dir = URL(fileURLWithPath: "/Users/rishizamvar/.claude/jobs/e1448d12/tmp/qa")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? app.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
  }
}
