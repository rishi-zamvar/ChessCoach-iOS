import ChessKit
import XCTest
@testable import ChessCoachKit

/// Scripted advisor: win% for the side to move per FEN key, best move default e2e4.
final class FakeCoach: CoachAdvisor, @unchecked Sendable {
  var wins: [String: Double] = [:]
  var best: [String: String] = [:]
  func assess(fen: String) async throws -> (bestUCI: String, winPercent: Double) {
    (best[FENTools.key(fen)] ?? "e2e4", wins[FENTools.key(fen)] ?? 50)
  }
}

@MainActor
final class PlayCoachTests: XCTestCase {
  func make(_ coach: FakeCoach, bot: [String]) -> (GameController, RecordingSoundSink, MemorySink) {
    let sounds = RecordingSoundSink()
    let sink = MemorySink()
    let c = GameController(
      config: PlayConfig(opponent: .maia(rating: 1100), userColor: .white, timeControl: .untimed),
      bot: ScriptedBot(bot), telemetry: Telemetry(sinks: [sink]), store: nil, sounds: sounds,
      minimumBotThink: .zero, coach: coach)
    return (c, sounds, sink)
  }

  func waitUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
  }

  func test_givenBlunder_whenCoachChecks_thenPausesWithBetterMoveAndTakeBackRestores() async {
    let coach = FakeCoach()
    var s = GameSession()
    s.apply(uci: "f2f3")
    coach.wins[FENTools.key(s.position.fen)] = 85  // opponent now winning
    let (c, _, sink) = make(coach, bot: ["e7e5"])
    c.start()
    c.tap(Square("f2"))
    c.tap(Square("f3"))
    await waitUntil { c.phase == .coachPaused }
    XCTAssertEqual(c.phase, .coachPaused)
    XCTAssertEqual(c.coachPause?.label, .blunder)
    XCTAssertEqual(c.coachPause?.bestSAN, "e4")
    c.showBetterMove()
    XCTAssertEqual(c.annotations.arrows.first?.from, Square("e2"))
    c.takeBack()
    XCTAssertEqual(c.session.history.count, 0)
    XCTAssertEqual(c.phase, .userTurn)
    XCTAssertFalse(sink.events(named: "coach.pause").isEmpty)
  }

  func test_givenBlunder_whenContinue_thenBotReplies() async {
    let coach = FakeCoach()
    var s = GameSession()
    s.apply(uci: "f2f3")
    coach.wins[FENTools.key(s.position.fen)] = 85
    let (c, _, _) = make(coach, bot: ["e7e5"])
    c.start()
    c.tap(Square("f2"))
    c.tap(Square("f3"))
    await waitUntil { c.phase == .coachPaused }
    c.continueGame()
    await c.waitForBot()
    XCTAssertEqual(c.session.history.map(\.san), ["f3", "e5"])
  }

  func test_givenGoodMove_whenCoachChecks_thenNoPauseAndBotReplies() async {
    let (c, _, _) = make(FakeCoach(), bot: ["e7e5"])
    c.start()
    c.tap(Square("e2"))
    c.tap(Square("e4"))
    await waitUntil { c.session.history.count == 2 }
    XCTAssertNil(c.coachPause)
    XCTAssertEqual(c.phase, .userTurn)
  }

  func test_givenHints_whenRequested_thenPieceThenHighlightThenArrow() async {
    let coach = FakeCoach()
    let (c, _, _) = make(coach, bot: [])
    c.start()
    await c.hint()
    XCTAssertEqual(c.hintText, "Look at your pawns.")
    await c.hint()
    XCTAssertEqual(c.annotations.circles[Square("e2")], .blue)
    await c.hint()
    XCTAssertEqual(c.annotations.arrows.first?.to, Square("e4"))
  }

  func test_givenBotHitsLoosePiece_whenNudged_thenWarnsOnce() async {
    // 1.Nc3 e5 2.Nd5 c6: the bot's pawn hits the undefended knight on d5.
    let (c, _, _) = make(FakeCoach(), bot: ["e7e5", "c7c6"])
    c.start()
    c.tap(Square("b1")); c.tap(Square("c3"))
    await waitUntil { c.session.history.count == 2 }
    c.tap(Square("c3")); c.tap(Square("d5"))
    await waitUntil { c.session.history.count == 4 }
    XCTAssertNotNil(c.nudge)
  }
}

@MainActor
final class PlayCoachRegressionTests: XCTestCase {
  func test_givenCoachPause_whenUserResigns_thenTakeBackCannotReviveGame() async {
    let coach = FakeCoach()
    var s = GameSession()
    s.apply(uci: "f2f3")
    coach.wins[FENTools.key(s.position.fen)] = 85
    let c = GameController(
      config: PlayConfig(opponent: .maia(rating: 1100), userColor: .white, timeControl: .untimed),
      bot: ScriptedBot(["e7e5"]), telemetry: Telemetry(sinks: []), store: nil, sounds: RecordingSoundSink(),
      minimumBotThink: .zero, coach: coach)
    c.start()
    c.tap(Square("f2")); c.tap(Square("f3"))
    for _ in 0..<200 where c.phase != .coachPaused { try? await Task.sleep(for: .milliseconds(10)) }
    c.resign()
    XCTAssertNil(c.coachPause)
    c.takeBack()
    XCTAssertTrue(c.isOver)
    XCTAssertEqual(c.session.history.count, 1)
  }
}

final class PuzzleUnderpromotionTests: XCTestCase {
  func test_givenKnightPromotionSolution_whenUserMovesPawn_thenExpectedPieceUsed() {
    // White to promote to a knight with check (fork-style); setup move is Black's king step.
    var s = PuzzleSession(puzzle: makePuzzle(fen: "k7/4P3/8/8/8/8/8/4K3 b - - 0 1", moves: ["a8b7", "e7e8n"], themes: ["underPromotion"]))
    s.playSetup()
    XCTAssertEqual(s.submit(uci: "e7e8"), .solved)
  }
}
