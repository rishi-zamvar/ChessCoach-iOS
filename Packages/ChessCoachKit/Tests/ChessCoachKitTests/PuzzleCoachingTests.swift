import XCTest
@testable import ChessCoachKit

/// W2 (every wrong move gets a why), W5 (other winning moves count).
final class PuzzleRefutationTests: XCTestCase {
  /// White's queen on d4 is attacked by the d8 rook.
  let hangingQueen = "3rk3/8/8/8/3Q4/8/8/4K3 w - - 0 1"
  /// White's rook guards the back rank; moving it lets Re1 mate.
  let backRank = "4r1k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"

  func test_givenWrongMove_whenPlayed_thenRefutationPliesAndFactCaptionProduced() throws {
    let r = try XCTUnwrap(PuzzleRefutation.make(fen: hangingQueen, wrong: "e1e2", punishLine: ["d8d4", "e2e3"]))
    XCTAssertEqual(r.reply, "d8d4")
    XCTAssertEqual(r.replySAN, "Rxd4")
    XCTAssertEqual(r.plies, ["d8d4"], "only the punishing reply is played out, not the whole line")
    XCTAssertEqual(r.caption, "Ke2 leaves the queen on d4: Rxd4 wins it.")
  }

  func test_givenWrongMoveAllowsMate_whenExplained_thenSaysMate() throws {
    let r = try XCTUnwrap(PuzzleRefutation.make(fen: backRank, wrong: "a1a2", punishLine: ["e8e1"]))
    XCTAssertEqual(r.caption, "Ra2 allows Re1#.")
  }

  func test_givenNoClearPunishment_whenExplained_thenHonestFallbackNamesTheReply() throws {
    let quiet = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"
    let r = try XCTUnwrap(PuzzleRefutation.make(fen: quiet, wrong: "e1d2", punishLine: ["e8d7"]))
    XCTAssertEqual(r.caption, "After Kd2 Kd7, the chance is gone. There's something stronger here.")
  }

  func test_givenIllegalOrMissingLine_whenExplained_thenNil() {
    XCTAssertNil(PuzzleRefutation.make(fen: hangingQueen, wrong: "e1e5", punishLine: ["d8d4"]))
    XCTAssertNil(PuzzleRefutation.make(fen: hangingQueen, wrong: "e1e2", punishLine: []))
  }
}

final class AlternativeWinTests: XCTestCase {
  // Scores are from the opponent's side (they're to move after your move), as the engine reports them.
  func test_givenAltMoveStillWinning_whenPlayed_thenCountsAsSolved() {
    XCTAssertTrue(AlternativeWin.accepts(afterYourMove: .centipawns(-450), afterSolution: .centipawns(-520)))
    XCTAssertTrue(AlternativeWin.accepts(afterYourMove: .mate(-2), afterSolution: .mate(-1)), "a slower mate still wins")
  }

  func test_givenAltMoveMuchWeakerOrNotWinning_whenPlayed_thenStillWrong() {
    XCTAssertFalse(AlternativeWin.accepts(afterYourMove: .centipawns(-150), afterSolution: .centipawns(-400)), "below +3")
    XCTAssertFalse(AlternativeWin.accepts(afterYourMove: .centipawns(-320), afterSolution: .mate(-3)), "misses a forced mate")
    XCTAssertFalse(AlternativeWin.accepts(afterYourMove: .centipawns(-350), afterSolution: .centipawns(-900)), "more than a pawn worse")
  }
}
