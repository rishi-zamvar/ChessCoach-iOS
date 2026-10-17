import XCTest

/// End-to-end: start a game vs Stockfish, play 1.e4, see the bot reply.
final class PlayUITests: XCTestCase {
  @MainActor
  func test_givenPlayTab_whenUserPlaysE4VsStockfish_thenBotRepliesInMoveStrip() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    snapshot(app, "01-today")

    app.tabBars.buttons["Play"].tap()
    XCTAssertTrue(app.buttons["opponent-stockfish"].waitForExistence(timeout: 5))
    app.buttons["opponent-stockfish"].tap()
    snapshot(app, "02-play-setup")
    app.buttons["play-start"].tap()

    let board = app.otherElements["board"]
    XCTAssertTrue(board.waitForExistence(timeout: 10))
    snapshot(app, "03-game-start")

    // e2 is file 5, rank 2 -> column 4, row 6 with White at the bottom.
    tap(board, column: 4, row: 6)
    tap(board, column: 4, row: 4)

    let strip = app.descendants(matching: .any)["move-strip"]
    XCTAssertTrue(strip.waitForExistence(timeout: 5))
    XCTAssertTrue(strip.buttons["e4"].waitForExistence(timeout: 5), "user move missing")
    // The bot's reply is the second button in the strip.
    let reply = NSPredicate(format: "count >= 2")
    expectation(for: reply, evaluatedWith: strip.buttons, handler: nil)
    waitForExpectations(timeout: 20)
    snapshot(app, "04-after-reply")

    // Select a piece to show legal-move dots.
    tap(board, column: 6, row: 7)
    snapshot(app, "05-selected-knight")

    app.buttons["toolbar-resign"].tap()
    app.buttons["confirm-resign"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["result-title"].waitForExistence(timeout: 5))
    snapshot(app, "06-result")

    app.buttons["result-review"].tap()
    let start = app.buttons["review-start"]
    XCTAssertTrue(start.waitForExistence(timeout: 60), "analysis never finished")
    snapshot(app, "07-review-summary")
    start.tap()
    XCTAssertTrue(app.staticTexts["coach-text"].waitForExistence(timeout: 5))
    snapshot(app, "08-review-moment")
    // Your own mistakes come with why + playable lines (only when this short game has one).
    if app.descendants(matching: .any)["review-insight"].waitForExistence(timeout: 2) {
      app.buttons["review-line-better"].tap()
      app.buttons["review-line-forward"].tap()
      snapshot(app, "09-review-better-line")
      app.buttons["review-line-end"].tap()
      XCTAssertTrue(app.descendants(matching: .any)["review-insight"].waitForExistence(timeout: 2))
    }
  }

  private func tap(_ board: XCUIElement, column: Int, row: Int) {
    let dx = (Double(column) + 0.5) / 8
    let dy = (Double(row) + 0.5) / 8
    board.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
  }

  @MainActor
  private func snapshot(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
