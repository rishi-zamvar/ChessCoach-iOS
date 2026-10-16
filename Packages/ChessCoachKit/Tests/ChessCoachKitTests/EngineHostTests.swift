import XCTest
@testable import ChessCoachKit

/// Live engine tests. They need the network files fetched by
/// `scripts/fetch-engine-assets.sh` into `ChessCoach/Resources/Engines`.
final class EngineHostTests: XCTestCase {
  static let enginesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // ChessCoachKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // ChessCoachKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repo root
    .appendingPathComponent("ChessCoach/Resources/Engines")

  static var assets: EngineAssets {
    EngineAssets(
      nnueBig: enginesDir.appendingPathComponent("nn-1111cefa1111.nnue"),
      nnueSmall: enginesDir.appendingPathComponent("nn-37f18f62d772.nnue"),
      maiaWeights: [1100: enginesDir.appendingPathComponent("maia-1100.pb.gz")]
    )
  }

  static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  /// White to move, Qh5xf7# is mate in 1 (Scholar's mate setup).
  static let mateInOneFEN = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"

  func test_givenMateInOne_whenStockfishSearches_thenFindsQxf7Mate() async throws {
    let host = EngineHost(assets: Self.assets)
    let result = try await host.search(.stockfish, fen: Self.mateInOneFEN, limit: .depth(10), multipv: 2)
    XCTAssertEqual(result.bestMove, "h5f7")
    XCTAssertEqual(result.lines.first?.score, .mate(1))
    XCTAssertEqual(result.lines.count, 2)
    await host.shutdown()
  }

  func test_givenStartPosition_whenMaiaSearchesOneNode_thenReturnsLegalMoveAndPolicy() async throws {
    let host = EngineHost(assets: Self.assets)
    let result = try await host.search(.maia(rating: 1100), fen: Self.startFEN, limit: .nodes(1))
    XCTAssertEqual(result.bestMove.count, 4)
    XCTAssertGreaterThan(result.policy.count, 10)
    XCTAssertEqual(result.policy.values.reduce(0, +), 1, accuracy: 0.01)
    await host.shutdown()
  }

  func test_givenOneHost_whenSwitchingStockfishToMaiaAndBack_thenBothAnswer() async throws {
    let host = EngineHost(assets: Self.assets)
    let sf1 = try await host.search(.stockfish, fen: Self.mateInOneFEN, limit: .depth(8))
    let maia = try await host.search(.maia(rating: 1100), fen: Self.startFEN, limit: .nodes(1))
    let sf2 = try await host.search(.stockfish, fen: Self.mateInOneFEN, limit: .depth(8))
    XCTAssertEqual(sf1.bestMove, "h5f7")
    XCTAssertFalse(maia.bestMove.isEmpty)
    XCTAssertEqual(sf2.bestMove, "h5f7")
    await host.shutdown()
  }

  func test_givenVerboseMoveStatsLine_whenParsed_thenExtractsMoveAndPrior() {
    let line = "e2e4  (322 ) N:       0 (+ 0) (P: 12.34%) (WL:  -.----) (D: -.---)"
    let parsed = EngineHost.parsePolicy(line)
    XCTAssertEqual(parsed?.0, "e2e4")
    XCTAssertEqual(parsed?.1 ?? 0, 0.1234, accuracy: 1e-9)
  }
}
