import XCTest
@testable import ChessCoachKit

/// W3: Coach mode — play it out, then find your own mistake.
final class CoachPuzzleTests: XCTestCase {
  /// Black's Kg8-h8 sets up White's back-rank mate Rd8#.
  let puzzle = makePuzzle(fen: "6k1/5ppp/8/8/8/8/5PPP/R2R2K1 b - - 0 1", moves: ["g8h8", "d1d8"])

  private func fresh() -> CoachPuzzleRun {
    var r = CoachPuzzleRun(puzzle: puzzle)
    r.playSetup()
    return r
  }

  func test_givenGoodMoves_whenPlayedOut_thenSolvedCleanAndRated() {
    var r = fresh()
    XCTAssertTrue(r.play(uci: "d1d8", loss: 0))
    XCTAssertEqual(r.phase, .solved, "mate ends the line")
    XCTAssertEqual(r.coachGrade, .clean)
    XCTAssertEqual(r.ratingScore, 1)
  }

  func test_givenCoachMode_whenMistakeThenGoodMoves_thenRevealAsksToFindMistake() {
    var r = fresh()
    XCTAssertTrue(r.play(uci: "a1a2", loss: 0.45), "a wrong move is accepted, not rejected")
    XCTAssertEqual(r.phase, .playing)
    XCTAssertTrue(r.awaitingOpponent)
    r.opponentPlays(uci: "h7h6")
    XCTAssertTrue(r.play(uci: "a2a3", loss: 0.02))
    XCTAssertEqual(r.phase, .findMistake, "the line ends after the solution's length plus one move")
    XCTAssertEqual(r.mistakeIndex, 0)
    XCTAssertEqual(r.ratingScore, 0, "first-move correctness drives the rating")
  }

  func test_givenCoachMode_whenUserPicksMistakeMove_thenRewindsToThatPosition() {
    var r = fresh()
    r.play(uci: "a1a2", loss: 0.45)
    r.opponentPlays(uci: "h7h6")
    r.play(uci: "a2a3", loss: 0.02)
    XCTAssertEqual(r.pick(1), .notThat)
    let fenBeforeMistake = r.moves[0].fenBefore
    XCTAssertEqual(r.pick(0), .found(fen: fenBeforeMistake))
    XCTAssertEqual(r.phase, .fixMistake(fen: fenBeforeMistake))
    r.fixed()
    XCTAssertEqual(r.phase, .done)
    XCTAssertEqual(r.coachGrade, .selfFound)
  }

  func test_givenTwoWrongPicks_whenPicking_thenMistakeIsShownAndGradeAssisted() {
    var r = fresh()
    r.play(uci: "a1a2", loss: 0.45)
    r.opponentPlays(uci: "h7h6")
    r.play(uci: "a2a3", loss: 0.02)
    XCTAssertEqual(r.pick(1), .notThat)
    XCTAssertEqual(r.pick(1), .revealed(index: 0))
    r.fixed()
    XCTAssertEqual(r.coachGrade, .assisted)
    XCTAssertEqual(r.grade(seconds: 20), .hard)
  }

  func test_givenFixRevealed_whenDone_thenGradeRevealedAndReviewAgain() {
    var r = fresh()
    r.play(uci: "a1a2", loss: 0.45)
    r.opponentPlays(uci: "h7h6")
    r.play(uci: "a2a3", loss: 0.02)
    _ = r.pick(0)
    r.revealFix()
    XCTAssertEqual(r.coachGrade, .revealed)
    XCTAssertEqual(r.grade(seconds: 20), .again)
  }

  func test_givenPuzzleSessionAndCoachRun_whenRecorded_thenBothArePuzzleOutcomes() {
    let outcomes: [any PuzzleOutcome] = [PuzzleSession(puzzle: puzzle), fresh()]
    XCTAssertEqual(outcomes.map(\.puzzle.id), [puzzle.id, puzzle.id])
  }
}
