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
      fenBeforeOpponent: "4k3/r7/8/3N4/8/8/8/4K3 b - - 0 1", opponentMove: "a7a8", fenNow: forkFEN, turn: 1)
    XCTAssertEqual(line, "I smell a fork. Which piece could hit two targets at once?")
    XCTAssertFalse(line!.contains("Nc7"))
  }

  func test_givenLoosePiece_whenPrompting_thenPointsAtIt() {
    let line = CoachVoice.prompt(
      fenBeforeOpponent: "4k3/8/8/1q6/8/8/8/3RK3 b - - 0 1", opponentMove: "b5d5", fenNow: "4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1",
      turn: 1)
    XCTAssertEqual(line, "Their queen looks loose. Can you win it?")
  }

  func test_givenQuietPosition_whenPrompting_thenOnlyOccasionalAdvice() {
    let fen = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    XCTAssertNil(CoachVoice.prompt(fenBeforeOpponent: "3k4/8/8/8/8/8/P7/4K3 b - - 0 1", opponentMove: "d8e8", fenNow: fen, turn: 3))
    XCTAssertNotNil(CoachVoice.prompt(fenBeforeOpponent: "3k4/8/8/8/8/8/P7/4K3 b - - 0 1", opponentMove: "d8e8", fenNow: fen, turn: 5))
  }

  func test_givenLines_whenSpoken_thenEveryOneHasARecordingWithAUniqueName() {
    let all = CoachVoice.allSpokenLines
    let produced = [
      CoachVoice.react(fenBefore: forkFEN, played: "e1d2", bestBefore: "d5c7"),
      CoachVoice.react(fenBefore: "4k3/8/4p3/8/8/2N5/8/4K3 w - - 0 1", played: "c3d5", bestBefore: nil),
      "Ah. You had checkmate there with Qh7#.", CoachVoice.sample,
    ].compactMap { $0 }
    for line in produced { XCTAssertTrue(all.contains(CoachVoice.spoken(line)), line) }
    XCTAssertEqual(CoachVoice.spoken("Hmm. You missed something. Nc7+ was a fork."), "Hmm. You missed something. You had a fork there.")
    XCTAssertEqual(CoachVoice.spoken("Hold up. Your knight on d5 has no defender."), "Hold up. Your knight has no defender.")
    XCTAssertTrue(all.contains("Hold up. Their bishop was free."))
    XCTAssertEqual(Set(all.map(CoachVoice.clipName)).count, Set(all).count)
  }

  /// `scripts/render-coach-voice.sh` runs this to get the lines to record.
  func test_dumpSpokenLines() throws {
    guard let out = ProcessInfo.processInfo.environment["COACH_LINES_OUT"] else { throw XCTSkip("render script only") }
    let rows = Set(CoachVoice.allSpokenLines).sorted().map { "\(CoachVoice.clipName($0))\t\($0)" }
    try rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
  }
}

