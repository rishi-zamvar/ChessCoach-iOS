import ChessCoachKit
import ChessKit
import XCTest
@testable import ChessCoach

@MainActor
final class FeedbackAndAccessibilityTests: XCTestCase {
  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: FeedbackCenter.shakeKey)
    super.tearDown()
  }

  func test_givenBoardActive_whenShake_thenFeedbackSheetNotShown() {
    UserDefaults.standard.set(true, forKey: FeedbackCenter.shakeKey)
    let center = AppEnvironment(inMemory: true).feedback
    center.boardsOpen = 1
    center.shake()
    XCTAssertEqual(center.opens, 0, "shaking the phone mid-puzzle must not open feedback")
    center.boardsOpen = 0
    center.shake()
    XCTAssertEqual(center.opens, 1)
  }

  func test_givenShakeOff_whenShake_thenNothing() {
    UserDefaults.standard.set(false, forKey: FeedbackCenter.shakeKey)
    let center = AppEnvironment(inMemory: true).feedback
    center.shake()
    XCTAssertEqual(center.opens, 0)
  }

  func test_givenBoard_whenVoiceOverReadsSquare_thenLabelNamesSquareAndPiece() {
    let e4 = Square("e4")
    XCTAssertEqual(BoardView.spoken(e4, Piece(.knight, color: .white, square: e4)), "e4, white knight")
    XCTAssertEqual(BoardView.spoken(Square("a8"), nil), "a8, empty")
  }

  func test_givenThumbsShownOnce_whenAnotherExplanationAppears_thenBudgetSaysNo() {
    let center = AppEnvironment(inMemory: true).feedback
    center.promptBudget = PromptBudget()
    XCTAssertTrue(center.promptBudget.mayShow(now: Date(), timedPlay: false))
    center.promptBudget.shown(now: Date())
    XCTAssertFalse(center.promptBudget.mayShow(now: Date(), timedPlay: false))
  }
}
