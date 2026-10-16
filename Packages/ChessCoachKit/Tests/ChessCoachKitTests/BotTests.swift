import ChessKit
import XCTest
@testable import ChessCoachKit

final class BotTests: XCTestCase {
  func test_givenSeededRandom_whenSampling_thenDeterministicAndFollowsWeights() {
    let policy = ["e2e4": 0.7, "d2d4": 0.2, "c2c4": 0.1]
    let a = (0..<200).map { _ in MaiaBot.sample(policy, temperature: 1, random: SeededRandom(seed: 7))! }
    let b = (0..<200).map { _ in MaiaBot.sample(policy, temperature: 1, random: SeededRandom(seed: 7))! }
    XCTAssertEqual(a, b)
    let rng = SeededRandom(seed: 42)
    let draws = (0..<2000).map { _ in MaiaBot.sample(policy, temperature: 1, random: rng)! }
    let e4Share = Double(draws.filter { $0 == "e2e4" }.count) / 2000
    XCTAssertEqual(e4Share, 0.7, accuracy: 0.05)
  }

  func test_givenZeroTemperature_whenSampling_thenAlwaysArgmax() {
    let policy = ["e2e4": 0.3, "d2d4": 0.6, "c2c4": 0.1]
    for seed in 0..<20 {
      XCTAssertEqual(MaiaBot.sample(policy, temperature: 0, random: SeededRandom(seed: UInt64(seed))), "d2d4")
    }
  }

  func test_givenEmptyPolicy_whenSampling_thenNil() {
    XCTAssertNil(MaiaBot.sample([:], temperature: 1, random: SeededRandom(seed: 1)))
  }

  func test_givenLevels_whenListed_thenEightAscendingRatings() {
    XCTAssertEqual(BotLevel.all.count, 8)
    XCTAssertEqual(BotLevel.all.map(\.displayRating), BotLevel.all.map(\.displayRating).sorted())
    XCTAssertEqual(BotLevel.level(99).level, 8)
    XCTAssertEqual(BotLevel.level(0).level, 1)
  }

  func test_givenMaiaBot_whenAskedForMoveFromStart_thenLegalMoveAndLogged() async throws {
    let sink = MemorySink()
    let host = EngineHost(assets: EngineHostTests.assets)
    let bot = MaiaBot(host: host, rating: 1100, random: SeededRandom(seed: 3), telemetry: Telemetry(sinks: [sink]))
    let uci = try await bot.move(fen: GameSession.standardFEN)
    var session = GameSession()
    XCTAssertNotEqual(session.apply(uci: uci), .illegal, uci)
    XCTAssertEqual(sink.events(named: "bot.move").map(\.phase), [.start, .finish])
    await host.shutdown()
  }

  func test_givenStrongStockfishBot_whenMateInOne_thenMates() async throws {
    let host = EngineHost(assets: EngineHostTests.assets)
    let bot = StockfishBot(host: host, level: .level(8), telemetry: Telemetry(sinks: []))
    let uci = try await bot.move(fen: EngineHostTests.mateInOneFEN)
    XCTAssertEqual(uci, "h5f7")
    await host.shutdown()
  }

  func test_givenWeakStockfishBot_whenAskedForMove_thenReturnsLegalMove() async throws {
    let host = EngineHost(assets: EngineHostTests.assets)
    let bot = StockfishBot(host: host, level: .level(1), telemetry: Telemetry(sinks: []))
    let uci = try await bot.move(fen: GameSession.standardFEN)
    var session = GameSession()
    XCTAssertNotEqual(session.apply(uci: uci), .illegal)
    await host.shutdown()
  }
}

final class TeachingBotExplanationTests: XCTestCase {
  let start = GameSession.standardFEN

  func test_givenExplanationAboutRealSquares_whenChecked_thenAccepted() {
    XCTAssertTrue(TeachingBot.isGrounded("I'm putting a pawn on e4 to take the centre.", fen: start, uci: "e2e4"))
    XCTAssertTrue(TeachingBot.isGrounded("e4 opens lines for my bishop on f1.", fen: start, uci: "e2e4"))
  }

  func test_givenExplanationNamingAnotherMove_whenChecked_thenRejected() {
    // Hints at a reply (Nf6) — never allowed.
    XCTAssertFalse(TeachingBot.isGrounded("e4, and if you play Nf6 I attack it.", fen: start, uci: "e2e4"))
  }

  func test_givenExplanationAboutEmptySquare_whenChecked_thenRejected() {
    XCTAssertFalse(TeachingBot.isGrounded("My queen on h5 is ready to strike.", fen: start, uci: "e2e4"))
  }
}

@MainActor
final class ExplainedBotTests: XCTestCase {
  struct TalkingBot: BotPlayer {
    var name: String { "Coach" }
    var rating: Int { 500 }
    var kind: String { "talking" }
    func move(fen: String) async throws -> String { "e7e5" }
    func explainedMove(fen: String) async throws -> (uci: String, why: String?) { ("e7e5", "I want my share of the centre.") }
  }

  func test_givenBotWithReason_whenItMoves_thenReasonKeptForThatPly() async {
    let c = GameController(
      config: PlayConfig(opponent: .teaching, userColor: .white, timeControl: .untimed),
      bot: TalkingBot(), telemetry: Telemetry(sinks: []), store: nil, sounds: RecordingSoundSink(), minimumBotThink: .zero)
    c.start()
    c.tap(Square("e2"))
    c.tap(Square("e4"))
    for _ in 0..<200 where c.session.history.count < 2 { try? await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(c.botReasons[2], "I want my share of the centre.")
    XCTAssertNil(c.botReasons[1])
  }
}
