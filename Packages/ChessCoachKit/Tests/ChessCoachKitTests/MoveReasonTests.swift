import XCTest
@testable import ChessCoachKit

final class MoveReasonTests: XCTestCase {
  func test_givenMateInOne_whenReasoned_thenSaysCheckmate() {
    let text = Explainer.reason(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", uci: "d1d8")
    XCTAssertEqual(text, "Rd8# is checkmate.")
  }

  func test_givenCaptureOfUndefendedPiece_whenReasoned_thenNamesWonPiece() {
    let text = Explainer.reason(fen: "4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1", uci: "d1d5")
    XCTAssertEqual(text, "Rxd5 wins the queen on d5.")
  }

  func test_givenEvenTrade_whenReasoned_thenSaysTakesBack() {
    // Knight takes a defended knight: an even trade.
    let text = Explainer.reason(fen: "4k3/8/4p3/3n4/8/4N3/8/4K3 w - - 0 1", uci: "e3d5")
    XCTAssertEqual(text, "Nxd5 trades on d5.")
  }

  func test_givenAttackedPieceRetreats_whenReasoned_thenSaysOutOfDanger() {
    // White's knight on d5 is attacked by the e6 pawn and steps back.
    let text = Explainer.reason(fen: "4k3/8/4p3/3N4/8/8/8/4K3 w - - 0 1", uci: "d5c3")
    XCTAssertEqual(text, "Nc3 moves the knight out of danger.")
  }

  func test_givenForkingMove_whenReasoned_thenListsTargets() {
    let text = Explainer.reason(fen: "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1", uci: "d5c7")
    XCTAssertEqual(text, "Nc7+ forks the king on e8 and rook on a8.")
  }

  func test_givenQuietMove_whenReasoned_thenFallsBackToPlainSentence() {
    let text = Explainer.reason(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", uci: "e2e4")
    XCTAssertEqual(text, "e4 improves the position.")
  }

  func test_givenIllegalMove_whenReasoned_thenNil() {
    XCTAssertNil(Explainer.reason(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", uci: "e2e5"))
  }
}
