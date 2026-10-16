import XCTest

/// Onboarding → Today plan → Train hub → a puzzle with hints → Openings.
final class TrainUITests: XCTestCase {
  @MainActor
  func test_givenFreshInstall_whenOnboardingAndTraining_thenPlanPuzzleAndOpeningsWork() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting", "-onboarding"]
    app.launch()

    XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: 10))
    shot(app, "10-onboarding-welcome")
    app.buttons["onboarding-start"].tap()
    sleep(1)
    shot(app, "10b-after-start")
    app.buttons["Skip"].tap()
    sleep(1)
    shot(app, "10c-after-skip")
    XCTAssertTrue(app.buttons["style-attacker"].waitForExistence(timeout: 5))
    app.buttons["style-attacker"].tap()
    shot(app, "11-onboarding-style")
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.buttons["quiz-sharp"].waitForExistence(timeout: 5))
    shot(app, "12-onboarding-quiz")
    for i in 0..<7 { (i % 3 == 0 ? app.buttons["quiz-quiet"] : app.buttons["quiz-sharp"]).tap() }
    // Placement: reveal each puzzle's solution to move on quickly.
    for i in 0..<10 {
      let hint = app.buttons["puzzle-hint"]
      XCTAssertTrue(hint.waitForExistence(timeout: 10), "placement puzzle \(i)")
      if i == 0 { shot(app, "13-onboarding-placement") }
      hint.tap(); hint.tap(); hint.tap()
      let next = app.buttons["puzzle-next"]
      app.buttons["puzzle-solution"].tap()
      XCTAssertTrue(next.waitForExistence(timeout: 3))
      if i == 0 {
        // The revealed solution steps forward one move at a time, each with a reason.
        let caption = app.descendants(matching: .any)["move-caption"]
        let before = caption.label
        app.buttons["step-forward"].tap()
        XCTAssertNotEqual(caption.label, before)
        XCTAssertTrue(caption.label.contains(":"), caption.label)
        shot(app, "13b-solution-step")
        app.buttons["step-back"].tap()
        // Retry replays the finished puzzle from the start.
        app.buttons["puzzle-retry"].tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertFalse(next.exists)
        hint.tap(); hint.tap(); hint.tap()
        app.buttons["puzzle-solution"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 3))
      }
      next.tap()
    }
    XCTAssertTrue(app.buttons["onboarding-finish"].waitForExistence(timeout: 10))
    shot(app, "14-onboarding-result")
    app.buttons["onboarding-finish"].tap()

    XCTAssertTrue(app.buttons["plan-start"].waitForExistence(timeout: 10))
    shot(app, "15-today-plan")

    app.tabBars.buttons["Train"].tap()
    XCTAssertTrue(app.staticTexts["puzzle-rating"].waitForExistence(timeout: 5))
    shot(app, "16-train-hub")
    app.buttons["skill-B1"].tap()
    XCTAssertTrue(app.buttons["puzzle-hint"].waitForExistence(timeout: 10))
    sleep(1)
    shot(app, "17-puzzle")
    app.buttons["puzzle-hint"].tap()
    app.buttons["puzzle-hint"].tap()
    shot(app, "18-puzzle-hint")
    app.buttons["runner-close"].tap()

    app.swipeUp()
    app.buttons["open-openings"].tap()
    XCTAssertTrue(app.staticTexts["Your repertoire"].waitForExistence(timeout: 5))
    shot(app, "19-openings")
  }

  @MainActor
  private func shot(_ app: XCUIApplication, _ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name
    a.lifetime = .keepAlways
    add(a)
  }
}
