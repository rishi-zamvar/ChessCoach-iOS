import XCTest

final class RushUITests: XCTestCase {
  @MainActor
  func test_givenTrain_whenPuzzleRushOpened_thenTimerScoreAndBoard() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    app.tabBars.buttons["Train"].tap()
    let rush = app.buttons["open-rush"]
    for _ in 0..<4 where !rush.isHittable { app.swipeUp() }
    rush.tap()
    XCTAssertTrue(app.staticTexts["rush-score"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.otherElements["board"].waitForExistence(timeout: 5))
    sleep(1)
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = "40-puzzle-rush"
    a.lifetime = .keepAlways
    add(a)
  }
}
