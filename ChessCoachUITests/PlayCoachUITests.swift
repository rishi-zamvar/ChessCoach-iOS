import XCTest

/// Play Coach: open it from Train, use the hint ladder.
final class PlayCoachUITests: XCTestCase {
  @MainActor
  func test_givenTrainTab_whenPlayCoachOpened_thenHintLadderShowsMove() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    app.tabBars.buttons["Train"].tap()
    let entry = app.buttons["play-coach"]
    for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
    entry.tap()
    let hint = app.buttons["toolbar-hint"]
    XCTAssertTrue(hint.waitForExistence(timeout: 10))
    // If the coach game started with us as Black, wait for the bot's first move.
    let enabled = NSPredicate(format: "isEnabled == true")
    expectation(for: enabled, evaluatedWith: hint, handler: nil)
    waitForExpectations(timeout: 20)
    for _ in 0..<3 {
      hint.tap()
      sleep(2)
    }
    XCTAssertTrue(app.descendants(matching: .any)["coach-banner"].waitForExistence(timeout: 10))
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = "20-play-coach-hint"
    a.lifetime = .keepAlways
    add(a)
  }
}
