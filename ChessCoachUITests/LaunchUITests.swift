import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func test_givenApp_whenLaunched_thenFourTabsExist() {
        let app = XCUIApplication()
        app.launch()
        for name in ["Today", "Analyze", "Train", "Play"] {
            XCTAssertTrue(app.tabBars.buttons[name].waitForExistence(timeout: 10), "missing tab \(name)")
        }
    }
}
