import ChessKit
import XCTest
@testable import ChessCoachKit

@MainActor
final class ReviewControllerTests: XCTestCase {
  /// Scholar's mate as Black: ply 6 (...Nf6??) is the user's blunder, best was ...g6 (g7g6).
  func makeController(sink: MemorySink = MemorySink()) -> ReviewController {
    let ucis = ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]
    var session = GameSession()
    var moves: [MoveAnalysis] = []
    for (i, uci) in ucis.enumerated() {
      let fen = session.position.fen
      let blunder = i == 5
      let sheet = FactExtractor.sheet(
        fen: fen, played: uci, bestLine: blunder ? ["g7g6", "h5f3"] : [uci], punishLine: blunder ? ["h5f7"] : [], ply: i)
      guard case .applied(let played) = session.apply(uci: uci) else { fatalError() }
      let label: MoveClass = blunder ? .blunder : (i < 4 ? .book : .best)
      moves.append(
        MoveAnalysis(
          ply: i + 1, san: played.san, uci: uci, color: i.isMultiple(of: 2) ? "white" : "black", fenBefore: fen,
          bestEP: 0.5, playedEP: blunder ? 0 : 0.5, bestUCI: blunder ? "g7g6" : uci, goodMoves: blunder ? ["g7g6", "d8e7"] : [],
          bestLine: sheet?.bestLineSAN ?? [], label: label, accuracy: blunder ? 0 : 100, facts: sheet,
          explanation: sheet.map { Explainer.explain($0, as: label, isUser: i % 2 == 1) } ?? "", mistakeType: blunder ? .allowedTactic : nil,
          timeTrouble: false, clock: nil))
    }
    let analysis = GameAnalysis(
      gameID: "g", engine: "stockfish-17", depth: 10, userColor: "black", startFEN: GameSession.standardFEN, moves: moves,
      whiteWin: Array(repeating: 50, count: 8), accuracyWhite: 100, accuracyBlack: 60, openingName: "Italian Game",
      createdAt: Date())
    return ReviewController(analysis: analysis, session: session, telemetry: Telemetry(sinks: [sink]))
  }

  func test_givenAnalysis_whenStartReview_thenJumpsToFirstKeyMomentWithExplanationAndArrows() {
    let c = makeController()
    c.startReview()
    XCTAssertEqual(c.ply, 6)
    XCTAssertEqual(c.currentMove?.label, .blunder)
    XCTAssertTrue(c.coachText.contains("Qxf7#"), c.coachText)
    XCTAssertEqual(c.annotations.arrows.map(\.color), [.green, .red])
    XCTAssertEqual(c.annotations.arrows.first?.from, Square("g7"))
  }

  func test_givenStart_whenNoMoveSelected_thenCoachMentionsOpening() {
    XCTAssertTrue(makeController().coachText.contains("Italian Game"))
  }

  func test_givenBlunder_whenRetryWithWrongMove_thenHintAndStillUnsolved() {
    let c = makeController()
    c.goTo(ply: 6)
    XCTAssertTrue(c.canRetry)
    c.retry()
    XCTAssertEqual(c.displayedFEN, c.session.fen(atPly: 5))
    c.retryDrag(from: Square("a7"), to: Square("a6"))
    XCTAssertEqual(c.retryState?.solved, false)
    XCTAssertEqual(c.retryState?.attempts, 1)
    XCTAssertTrue(c.coachText.contains("a6 isn't it"), c.coachText)
  }

  func test_givenBlunder_whenRetryWithBestMove_thenSolvedAndBoardShowsIt() {
    let c = makeController()
    c.goTo(ply: 6)
    c.retry()
    c.retryTap(Square("g7"))
    c.retryTap(Square("g6"))
    XCTAssertEqual(c.retryState?.solved, true)
    XCTAssertTrue(c.coachText.hasPrefix("That's it!"), c.coachText)
    XCTAssertNotEqual(c.displayedFEN, c.session.fen(atPly: 5))
  }

  func test_givenRetry_whenAlternativeGoodMovePlayed_thenAlsoAccepted() {
    let c = makeController()
    c.goTo(ply: 6)
    c.retry()
    c.retryDrag(from: Square("d8"), to: Square("e7"))
    XCTAssertEqual(c.retryState?.solved, true)
  }

  func test_givenRetry_whenHintsRequested_thenLadderEndsInReveal() {
    let c = makeController()
    c.goTo(ply: 6)
    c.retry()
    c.hint()
    XCTAssertTrue(c.coachText.hasPrefix("Hint"), c.coachText)
    c.hint()
    XCTAssertEqual(c.annotations.circles[Square("g7")], .blue)
    c.hint()
    XCTAssertEqual(c.retryState?.revealed, true)
    XCTAssertTrue(c.coachText.contains("The move was g6"), c.coachText)
  }

  func test_givenGoodMove_whenSelected_thenNoRetryAndNoArrows() {
    let c = makeController()
    c.goTo(ply: 7)
    XCTAssertFalse(c.canRetry)
    XCTAssertTrue(c.annotations.arrows.isEmpty)
  }

  func test_givenMoments_whenNavigating_thenNextAndPreviousMoment() {
    let c = makeController()
    c.goTo(ply: 2)
    c.nextMoment()
    XCTAssertEqual(c.ply, 6)
    c.nextMoment()
    XCTAssertEqual(c.ply, 7)
    c.previousMoment()
    XCTAssertEqual(c.ply, 6)
  }

  func test_givenBlunder_whenInsightAndLines_thenExplainsAndPlaysYourLineAndTheBetterOne() throws {
    let c = makeController()
    c.goTo(ply: 6)
    let insight = try XCTUnwrap(c.insight)
    XCTAssertTrue(insight.played.contains("Qxf7#"), insight.played)
    XCTAssertFalse(insight.better.isEmpty)
    XCTAssertFalse(insight.habit.isEmpty)

    c.playLine(better: false)
    XCTAssertEqual(c.displayedFEN, c.session.fen(atPly: 5), "lines start from the position before your move")
    c.lineForward()
    XCTAssertEqual(c.displayedFEN, c.session.fen(atPly: 6), "first your move")
    c.lineForward()
    XCTAssertTrue(c.coachText.contains("checkmate"), c.coachText)
    c.lineBack()
    XCTAssertEqual(c.displayedFEN, c.session.fen(atPly: 6))

    c.playLine(better: true)
    c.lineForward()
    XCTAssertNotEqual(c.displayedFEN, c.session.fen(atPly: 6), "the better move, not yours")
    c.goTo(ply: 7)
    XCTAssertNil(c.line, "moving on ends the line")
  }

  func test_givenWrongRetries_whenHinting_thenNeverGivesThePieceAwayUnasked() {
    let c = makeController()
    c.goTo(ply: 6)
    c.retry()
    let move = c.analysis.moves[5]
    let wrong = BoardScan.legalUCIs(fen: c.session.fen(atPly: 5)).first { $0 != move.bestUCI && !move.goodMoves.contains($0) }!
    let (from, to) = (Square(String(wrong.prefix(2))), Square(String(wrong.dropFirst(2).prefix(2))))
    c.retryDrag(from: from, to: to)
    c.retryDrag(from: from, to: to)
    XCTAssertEqual(c.retryState?.attempts, 2)
    XCTAssertEqual(c.retryState?.hintLevel, 1)
  }

  func test_givenReview_whenStartedAndRetried_thenLogged() {
    let sink = MemorySink()
    let c = makeController(sink: sink)
    c.startReview()
    c.retry()
    c.retryDrag(from: Square("g7"), to: Square("g6"))
    XCTAssertEqual(Set(sink.events.map(\.step)), ["review.start", "review.retry", "review.attempt"])
  }
}
