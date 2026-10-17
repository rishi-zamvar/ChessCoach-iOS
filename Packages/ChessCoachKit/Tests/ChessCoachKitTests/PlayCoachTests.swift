import ChessKit
import XCTest
@testable import ChessCoachKit

/// Scripted advisor: win% for the side to move per FEN key, best move default e2e4.
final class FakeCoach: CoachAdvisor, @unchecked Sendable {
  var wins: [String: Double] = [:]
  var best: [String: String] = [:]
  var mates: [String: Int] = [:]
  func assess(fen: String) async throws -> CoachAssessment {
    let key = FENTools.key(fen)
    return CoachAssessment(bestUCI: best[key] ?? "e2e4", winPercent: wins[key] ?? 50, mate: mates[key])
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

  func test_givenFreePieceSkipped_whenCoachChecks_thenHoldUpMarksItSpeaksAndCounts() async {
    let fen = "4k3/8/8/3b4/8/8/8/3RK3 w - - 0 1"
    let coach = FakeCoach()
    var s = GameSession(startFEN: fen)
    s.apply(uci: "e1e2")
    coach.wins[FENTools.key(s.position.fen)] = 80
    coach.best[FENTools.key(fen)] = "d1d5"
    let c = GameController(
      config: PlayConfig(opponent: .teaching, userColor: .white, timeControl: .untimed),
      bot: ScriptedBot(["e8e7"]), telemetry: Telemetry(sinks: []), store: nil, sounds: RecordingSoundSink(),
      startFEN: fen, minimumBotThink: .zero, coach: coach, voice: coach, focus: .freePieces)
    c.start()
    // A position with few pieces starts straight in the endgame.
    XCTAssertEqual(c.stage, .endgame)
    XCTAssertEqual(c.coachLine?.headline, CoachVoice.endgameStart)
    c.tap(Square("e1"))
    c.tap(Square("e2"))
    await waitUntil { c.phase == .coachPaused }
    XCTAssertEqual(c.coachPause?.kind, .missedFree)
    XCTAssertEqual(c.coachPause?.title, "Hold up: a free piece")
    XCTAssertEqual(c.annotations.circles[Square("d5")], .green)
    XCTAssertEqual(c.coachLine?.text, "Hold up. Their bishop on d5 was free.")
    XCTAssertEqual(c.tally.missedFree, 1)
    c.takeBack()
    XCTAssertEqual(c.session.history.count, 0)
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

  func test_givenVoiceCoach_whenBotHangsQueen_thenCoachPointsAtItWithoutTheMove() async {
    let voice = FakeCoach()
    let start = "4k3/8/8/1q6/8/8/8/3RK3 w - - 0 1"
    var s = GameSession(startFEN: start)
    s.apply(uci: "e1f2")
    s.apply(uci: "b5d5")
    voice.best[FENTools.key(s.position.fen)] = "d1d5"
    let c = GameController(
      config: PlayConfig(opponent: .maia(rating: 1100), userColor: .white, timeControl: .untimed),
      bot: ScriptedBot(["b5d5"]), telemetry: Telemetry(sinks: []), store: nil, sounds: RecordingSoundSink(),
      startFEN: start, minimumBotThink: .zero, voice: voice)
    c.start()
    c.tap(Square("e1"))
    c.tap(Square("f2"))
    await waitUntil { c.coachLine != nil }
    XCTAssertEqual(c.coachLine?.text, "Their queen looks loose. Can you win it?")
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
