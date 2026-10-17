import XCTest

/// Screenshot tour with real data: imports Zammy009's chess.com games and reviews one.
/// Needs network (chess.com). Captures screens for the status report.
final class TourUITests: XCTestCase {
  @MainActor
  func test_tour_realGamesReviewLessonsOpenings() throws {
    // Needs network + ~2 min: run with TEST_RUNNER_TOUR=1 xcodebuild test -only-testing:ChessCoachUITests/TourUITests
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TOUR"] == "1", "set TEST_RUNNER_TOUR=1")
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()

    shot(app, "30-today")
    app.tabBars.buttons["Analyze"].tap()
    // Import runs on its own when no games are stored; pulling down refreshes it too.
    if app.staticTexts["import-status"].waitForExistence(timeout: 5) {
      app.scrollViews.firstMatch.swipeDown(velocity: .fast)
    }
    let firstGame = app.descendants(matching: .any)["game-row-0"]
    XCTAssertTrue(firstGame.waitForExistence(timeout: 60), "no games imported")
    sleep(2)
    shot(app, "31-analyze-imported")
    firstGame.tap()
    let start = app.buttons["review-start"]
    XCTAssertTrue(start.waitForExistence(timeout: 240), "review never finished")
    shot(app, "32-review-real-summary")
    start.tap()
    sleep(1)
    shot(app, "33-review-real-moment")
    if app.descendants(matching: .any)["review-insight"].exists {
      app.buttons["review-line-yours"].tap()
      app.buttons["review-line-forward"].tap()
      app.buttons["review-line-forward"].tap()
      shot(app, "33b-review-your-line")
      app.buttons["review-line-end"].tap()
    }
    if app.buttons["review-retry"].exists {
      app.buttons["review-retry"].tap()
      sleep(1)
      shot(app, "34-review-retry")
    }
    app.buttons["review-close"].tap()
    sleep(1)
    shot(app, "35-analyze-after-review")

    app.tabBars.buttons["Train"].tap()
    app.swipeUp()
    sleep(1)
    shot(app, "36-train-lessons")
    let lesson = app.buttons["Queen + King mate"].firstMatch
    if lesson.exists {
      lesson.tap()
      XCTAssertTrue(app.buttons["lesson-next"].waitForExistence(timeout: 5))
      shot(app, "37-lesson-idea")
      app.buttons["lesson-next"].tap()
      sleep(1)
      if app.buttons["lesson-step"].exists { app.buttons["lesson-step"].tap(); sleep(1) }
      shot(app, "38-lesson-worked")
      app.buttons["runner-close"].tap()
    }
    app.swipeUp()
    let openings = app.buttons["open-openings"]
    if openings.waitForExistence(timeout: 3) {
      openings.tap()
      let learn = app.buttons["Learn"].firstMatch
      if learn.waitForExistence(timeout: 5) {
        learn.tap()
        sleep(2)
        shot(app, "39-openings-learn")
      }
    }
  }

  @MainActor
  private func shot(_ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
}
