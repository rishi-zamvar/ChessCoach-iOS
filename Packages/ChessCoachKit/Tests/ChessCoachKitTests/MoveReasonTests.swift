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
    let text = Explainer.reason(fen: "4k3/8/8/8/8/8/P7/4K3 w - - 0 1", uci: "a2a3")
    XCTAssertEqual(text, "a3 is a quiet move.")
  }

  func test_givenCentrePawnPush_whenReasoned_thenClaimsCentre() {
    XCTAssertEqual(Explainer.reason(fen: GameSession.standardFEN, uci: "e2e4"), "e4 claims the centre.")
  }

  func test_givenKnightOffBackRank_whenReasoned_thenDevelops() {
    XCTAssertEqual(Explainer.reason(fen: GameSession.standardFEN, uci: "g1f3"), "Nf3 develops the knight.")
  }

  func test_givenCastling_whenReasoned_thenTucksKingAway() {
    let text = Explainer.reason(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1", uci: "e1g1")
    XCTAssertEqual(text, "O-O castles, tucking the king away.")
  }

  func test_givenMoveHittingUndefendedPiece_whenReasoned_thenSaysAttacks() {
    // Bb5 hits the undefended knight on c6... use a lone knight on c6 with no defenders.
    let text = Explainer.reason(fen: "7k/8/2n5/8/8/8/8/4KB2 w - - 0 1", uci: "f1b5")
    XCTAssertEqual(text, "Bb5 attacks the knight on c6.")
  }

  func test_givenIllegalMove_whenReasoned_thenNil() {
    XCTAssertNil(Explainer.reason(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", uci: "e2e5"))
  }
}
