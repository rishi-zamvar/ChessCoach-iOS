import XCTest
@testable import ChessCoachKit

final class CoachVoiceTests: XCTestCase {
  let forkFEN = "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1"

  func test_givenMissedFork_whenReacting_thenNamesTheForkAfterwards() {
    let line = CoachVoice.react(fenBefore: forkFEN, played: "e1d2", bestBefore: "d5c7")
    XCTAssertEqual(line, "Hmm. You missed something. Nc7+ was a fork.")
  }

  func test_givenPlayedFork_whenReacting_thenPraises() {
    XCTAssertEqual(CoachVoice.react(fenBefore: forkFEN, played: "d5c7", bestBefore: "d5c7"), "Lovely fork. Two targets, one move.")
  }

  func test_givenMoveHangingAPiece_whenReacting_thenWarns() {
    // Knight steps next to a pawn that can take it.
    let line = CoachVoice.react(fenBefore: "4k3/8/4p3/8/8/2N5/8/4K3 w - - 0 1", played: "c3d5", bestBefore: nil)
    XCTAssertEqual(line, "Careful. Your knight on d5 can be taken now.")
  }

  func test_givenForkAvailable_whenPrompting_thenHintsWithoutNamingMove() {
    // Black's last move ...Ra8 walked into the fork.
    let line = CoachVoice.prompt(
      fenBeforeOpponent: "4k3/r7/8/3N4/8/8/8/4K3 b - - 0 1", opponentMove: "a7a8", fenNow: forkFEN, best: "d5c7", turn: 1)
    XCTAssertEqual(line, "I smell a fork. Which piece could hit two targets at once?")
    XCTAssertFalse(line!.contains("Nc7"))
  }

  func test_givenLoosePiece_whenPrompting_thenPointsAtIt() {
    let line = CoachVoice.prompt(
      fenBeforeOpponent: "4k3/8/8/1q6/8/8/8/3RK3 b - - 0 1", opponentMove: "b5d5", fenNow: "4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1",
      best: "d1d5", turn: 1)
    XCTAssertEqual(line, "Their queen looks loose. Can you win it?")
  }

  func test_givenQuietPosition_whenPrompting_thenOnlyOccasionalAdvice() {
    let fen = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    XCTAssertNil(CoachVoice.prompt(fenBeforeOpponent: "3k4/8/8/8/8/8/P7/4K3 b - - 0 1", opponentMove: "d8e8", fenNow: fen, best: "a2a3", turn: 3))
    XCTAssertNotNil(CoachVoice.prompt(fenBeforeOpponent: "3k4/8/8/8/8/8/P7/4K3 b - - 0 1", opponentMove: "d8e8", fenNow: fen, best: "a2a3", turn: 5))
  }
}
