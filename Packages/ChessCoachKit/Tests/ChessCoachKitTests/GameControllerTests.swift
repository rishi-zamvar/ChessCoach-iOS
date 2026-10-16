import ChessKit
import XCTest
@testable import ChessCoachKit

/// Plays a scripted list of UCI moves.
final class ScriptedBot: BotPlayer, @unchecked Sendable {
  var moves: [String]
  var fail = false
  init(_ moves: [String]) { self.moves = moves }
  let name = "Scripted"
  let rating = 1000
  let kind = "scripted"
  struct Failure: Error {}
  func move(fen: String) async throws -> String {
    if fail { throw Failure() }
    return moves.isEmpty ? "" : moves.removeFirst()
  }
}

@MainActor
final class GameControllerTests: XCTestCase {
  var now = Date(timeIntervalSince1970: 1_000)
  var sounds: RecordingSoundSink!
  var sink: MemorySink!
  var store: GameStore!

  override func setUp() async throws {
    sounds = RecordingSoundSink()
    sink = MemorySink()
    store = GameStore(database: try AppDatabase.inMemory())
  }

  func make(
    bot: ScriptedBot, color: Piece.Color = .white, time: TimeControl = .untimed, startFEN: String = GameSession.standardFEN
  ) -> GameController {
    GameController(
      config: PlayConfig(opponent: .maia(rating: 1100), userColor: color, timeControl: time),
      bot: bot, telemetry: Telemetry(sinks: [sink]), store: store, sounds: sounds,
      startFEN: startFEN, minimumBotThink: .zero, now: { [unowned self] in self.now })
  }

  func test_givenStartedGame_whenUserMoves_thenBotReplies() async {
    let controller = make(bot: ScriptedBot(["e7e5"]))
    controller.start()
    controller.tap(Square("e2"))
    controller.tap(Square("e4"))
    await controller.waitForBot()
    XCTAssertEqual(controller.session.history.map(\.san), ["e4", "e5"])
    XCTAssertEqual(controller.phase, .userTurn)
    XCTAssertEqual(sounds.played, [.gameStart, .move, .move])
  }

  func test_givenUserIsBlack_whenStarted_thenBotMovesFirst() async {
    let controller = make(bot: ScriptedBot(["d2d4"]), color: .black)
    XCTAssertTrue(controller.flipped)
    controller.start()
    await controller.waitForBot()
    XCTAssertEqual(controller.session.history.map(\.san), ["d4"])
    XCTAssertEqual(controller.phase, .userTurn)
  }

  func test_givenMateAvailable_whenUserMates_thenGameOverSavedWithPGN() async throws {
    let controller = make(bot: ScriptedBot(["e7e5", "b8c6", "g8f6"]))
    controller.start()
    for (from, to) in [("e2", "e4"), ("f1", "c4"), ("d1", "h5")] {
      controller.tap(Square(from))
      controller.tap(Square(to))
      await controller.waitForBot()
    }
    controller.tap(Square("h5"))
    controller.tap(Square("f7"))
    XCTAssertEqual(controller.phase, .over(GameResult(winner: .white, termination: .checkmate)))
    XCTAssertEqual(sounds.played.last, .gameEnd)
    let saved = try store.recent()
    XCTAssertEqual(saved.count, 1)
    XCTAssertEqual(saved[0].result, "1-0")
    XCTAssertEqual(saved[0].termination, "checkmate")
    XCTAssertTrue(saved[0].pgn.contains("Qxf7#"))
    XCTAssertEqual(saved[0].opponentKind, "scripted")
    XCTAssertFalse(sink.events(named: "game.end").isEmpty)
  }

  func test_givenPremoveQueued_whenBotReplies_thenPremovePlaysAutomatically() async {
    let bot = ScriptedBot(["e7e5", "b8c6"])
    let controller = make(bot: bot)
    controller.start()
    controller.tap(Square("e2"))
    controller.tap(Square("e4"))
    // Bot hasn't replied yet (task pending): queue g1f3 as a premove.
    controller.tap(Square("g1"))
    controller.tap(Square("f3"))
    await controller.waitForBot()
    await controller.waitForBot()
    XCTAssertEqual(controller.session.history.map(\.san), ["e4", "e5", "Nf3", "Nc6"])
    XCTAssertTrue(sounds.played.contains(.premove))
  }

  func test_givenIllegalPremove_whenBotReplies_thenDiscarded() async {
    // Premove e4-e5 becomes illegal after ...e5 blocks it.
    let controller = make(bot: ScriptedBot(["e7e5"]))
    controller.start()
    controller.tap(Square("e2"))
    controller.tap(Square("e4"))
    controller.tap(Square("e4"))
    controller.tap(Square("e5"))
    await controller.waitForBot()
    XCTAssertEqual(controller.session.history.map(\.san), ["e4", "e5"])
    XCTAssertEqual(controller.phase, .userTurn)
    XCTAssertNil(controller.interaction.premove)
  }

  func test_givenPromotionMove_whenTapped_thenWaitsForChoiceThenPromotes() async {
    // Black keeps a pawn so K+N vs K+P is not an insufficient-material draw.
    let controller = make(bot: ScriptedBot(["a2a1"]), startFEN: "8/4P3/8/8/8/7p/k7/4K3 w - - 0 1")
    controller.start()
    controller.tap(Square("e7"))
    controller.tap(Square("e8"))
    XCTAssertEqual(controller.pendingPromotion?.to, Square("e8"))
    XCTAssertEqual(controller.session.history.count, 0)
    controller.choosePromotion(.knight)
    XCTAssertNil(controller.pendingPromotion)
    XCTAssertTrue(controller.session.history.first?.san.hasPrefix("e8=N") ?? false)
    XCTAssertEqual(sounds.played.dropFirst().first, .promote)
  }

  func test_givenTimedGame_whenUserClockRunsOut_thenFlagEndsGame() {
    let controller = make(bot: ScriptedBot([]), time: .init(base: 60, increment: 0))
    controller.start()
    now += 61
    controller.tick()
    XCTAssertEqual(controller.phase, .over(GameResult(winner: .black, termination: .timeout)))
  }

  func test_givenTimedGame_whenUserClockLow_thenLowTimeSoundOnce() {
    let controller = make(bot: ScriptedBot([]), time: .init(base: 60, increment: 0))
    controller.start()
    now += 45
    controller.tick()
    controller.tick()
    XCTAssertEqual(sounds.played.filter { $0 == .lowTime }.count, 1)
  }

  func test_givenGame_whenUserResigns_thenOverAndSaved() throws {
    let controller = make(bot: ScriptedBot([]))
    controller.start()
    controller.resign()
    XCTAssertEqual(controller.phase, .over(GameResult(winner: .black, termination: .resignation)))
    XCTAssertEqual(try store.recent().first?.result, "0-1")
  }

  func test_givenMovesPlayed_whenBrowsingBack_thenBoardTapsIgnoredUntilLatest() async {
    let controller = make(bot: ScriptedBot(["e7e5"]))
    controller.start()
    controller.tap(Square("e2"))
    controller.tap(Square("e4"))
    await controller.waitForBot()
    controller.stepBack()
    XCTAssertEqual(controller.viewPly, 1)
    XCTAssertFalse(controller.isViewingLatest)
    controller.tap(Square("g1"))
    XCTAssertNil(controller.interaction.selected)
    controller.stepForward()
    XCTAssertTrue(controller.isViewingLatest)
    XCTAssertEqual(controller.displayedFEN, controller.session.position.fen)
  }

  func test_givenBotThrows_whenItsTurn_thenFallsBackToLegalMoveAndLogsFailure() async {
    let bot = ScriptedBot([])
    bot.fail = true
    let controller = make(bot: bot)
    controller.start()
    controller.tap(Square("e2"))
    controller.tap(Square("e4"))
    await controller.waitForBot()
    XCTAssertEqual(controller.session.history.count, 2)
    XCTAssertEqual(controller.phase, .userTurn)
    XCTAssertFalse(sink.events(named: "game.botFallback").isEmpty)
  }

  func test_givenAnyGame_whenPhasesChange_thenEveryTransitionLogged() async {
    let controller = make(bot: ScriptedBot(["e7e5"]))
    controller.start()
    controller.tap(Square("e2"))
    controller.tap(Square("e4"))
    await controller.waitForBot()
    controller.resign()
    let steps = Set(sink.events.map(\.step))
    XCTAssertTrue(steps.isSuperset(of: ["game.start", "game.move", "game.end", "game.botTurn"]), "\(steps)")
    let moves = sink.events(named: "game.move")
    XCTAssertEqual(moves.count, 2)
    XCTAssertEqual(moves.first?.metadata["san"], .string("e4"))
  }

  func test_givenOpeningPosition_whenDrawOffered_thenBotDeclines() {
    let controller = make(bot: ScriptedBot([]))
    controller.start()
    XCTAssertFalse(controller.offerDraw())
    XCTAssertEqual(controller.phase, .userTurn)
  }
}
