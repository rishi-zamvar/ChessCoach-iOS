import XCTest
@testable import ChessCoachKit

/// W4: the analysis board's line — any legal move for either side, undo/redo, reset, export.
final class AnalysisLineTests: XCTestCase {
  func test_givenAnalysisBoard_whenAnyLegalMove_thenEvalUpdatesAndUndoRestores() {
    var line = AnalysisLine(startFEN: GameSession.standardFEN)
    XCTAssertTrue(line.play(uci: "e2e4"))
    XCTAssertTrue(line.play(uci: "e7e5"), "either side can move")
    XCTAssertFalse(line.play(uci: "e1e8"), "illegal moves are refused")
    let afterTwo = line.fen
    XCTAssertTrue(line.undo())
    XCTAssertEqual(line.cursor, 1)
    XCTAssertTrue(line.redo())
    XCTAssertEqual(line.fen, afterTwo)
    XCTAssertEqual(line.san, ["e4", "e5"])
  }

  func test_givenRewoundLine_whenPlayingNewMove_thenFutureIsReplaced() {
    var line = AnalysisLine(startFEN: GameSession.standardFEN, moves: ["e2e4", "e7e5", "g1f3"])
    XCTAssertEqual(line.cursor, 3)
    line.undo()
    line.undo()
    XCTAssertTrue(line.play(uci: "c7c5"))
    XCTAssertEqual(line.san, ["e4", "c5"])
    XCTAssertFalse(line.canRedo)
    line.reset()
    XCTAssertEqual(line.fen, GameSession.standardFEN)
  }

  func test_givenLine_whenExported_thenPGNCarriesStartPosition() {
    let fen = "6k1/5ppp/8/8/8/8/5PPP/R2R2K1 w - - 0 1"
    var line = AnalysisLine(startFEN: fen)
    line.play(uci: "d1d8")
    XCTAssertTrue(line.pgn.contains("[FEN \"\(fen)\"]"))
    XCTAssertTrue(line.pgn.contains("1. Rd8#"))
  }

  func test_givenAltWinningMove_whenAccepted_thenSolvedWithoutAFailure() {
    let puzzle = makePuzzle(fen: "6k1/5ppp/8/8/8/8/5PPP/R2R2K1 b - - 0 1", moves: ["g8h8", "d1d8"])
    var s = PuzzleSession(puzzle: puzzle)
    s.playSetup()
    XCTAssertEqual(s.submit(uci: "a1a8"), .solved, "any mate on the last move already counts")
    var t = PuzzleSession(puzzle: makePuzzle(fen: "6k1/5ppp/8/8/8/8/5PPP/R2R2K1 b - - 0 1", moves: ["g8h8", "d1d8", "h8h7", "a1a7"]))
    t.playSetup()
    XCTAssertEqual(t.submit(uci: "d1d7"), .wrong)
    XCTAssertTrue(t.acceptAlternative(uci: "d1d7"))
    XCTAssertTrue(t.isSolved)
    XCTAssertFalse(t.failedFirstTry, "the engine-approved move isn't held against you")
    XCTAssertEqual(t.solvedByAlternative, "d1d7")
  }
}
