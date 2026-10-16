import ChessCoachKit
import XCTest
@testable import ChessCoach

final class AnalyzeTests: XCTestCase {
  func test_givenExportedPGNWithCastlingPromotionAndClocks_whenReplayed_thenSANAndFENMatch() throws {
    var original = GameSession()
    let moves = ["e2e4", "d7d5", "e4d5", "c7c6", "d5c6", "g8f6", "g1f3", "e7e6", "f1e2", "f8e7",
                 "e1g1", "e8g8", "c6b7", "b8d7", "b7a8q"]
    for (i, uci) in moves.enumerated() {
      guard case .applied = original.apply(uci: uci) else { return XCTFail("illegal \(uci)") }
      original.setClockAfterLastMove(TimeInterval(300 - i))
    }
    let pgn = original.pgn(tags: ["White": "You", "Black": "Maia 1100"])
    XCTAssertTrue(pgn.contains("{[%clk"))
    XCTAssertTrue(pgn.contains("O-O"))
    XCTAssertTrue(pgn.contains("=Q"))

    let replayed = try XCTUnwrap(GameSession(pgn: pgn))
    XCTAssertEqual(replayed.history.map(\.san), original.history.map(\.san))
    XCTAssertEqual(replayed.history.map(\.uci), moves)
    XCTAssertEqual(replayed.position.fen, original.position.fen)
  }

  func test_givenEmptyGamePGN_whenReplayed_thenSessionHasNoMoves() throws {
    let pgn = GameSession().pgn(tags: [:])
    XCTAssertEqual(try XCTUnwrap(GameSession(pgn: pgn)).history.count, 0)
  }

  func test_givenMalformedPGN_whenReplayed_thenNil() {
    XCTAssertNil(GameSession(pgn: "1. e4 e5 2. Ke4 *"))
    XCTAssertNil(GameSession(pgn: "1. e4 } e5 *"))
    XCTAssertNil(GameSession(pgn: "hello world"))
    XCTAssertNil(GameSession(pgn: "[White \"x\"]\n\n1. e4\n\n2. e5\n\n3. Nf3"))
  }

  func test_givenUserColorAndResult_whenMappingOutcome_thenWinLossDraw() {
    XCTAssertEqual(GameOutcome(userColor: "white", result: "1-0"), .win)
    XCTAssertEqual(GameOutcome(userColor: "white", result: "0-1"), .loss)
    XCTAssertEqual(GameOutcome(userColor: "black", result: "0-1"), .win)
    XCTAssertEqual(GameOutcome(userColor: "black", result: "1-0"), .loss)
    XCTAssertEqual(GameOutcome(userColor: "white", result: "1/2-1/2"), .draw)
    XCTAssertEqual(GameOutcome(userColor: "black", result: "1/2-1/2"), .draw)
  }

  func test_givenMixedSources_whenFiltering_thenOnlyMatchingGames() {
    func game(_ id: String, _ source: GameRecord.Source) -> GameRecord {
      GameRecord(
        id: id, source: source, pgn: "", white: "a", black: "b", userColor: "white", result: "1-0",
        termination: "", timeControl: "", opponentKind: "", startedAt: .now, endedAt: .now)
    }
    let games = [game("1", .local), game("2", .chesscom), game("3", .local)]
    XCTAssertEqual(GameFilter.all.apply(games).map(\.id), ["1", "2", "3"])
    XCTAssertEqual(GameFilter.chesscom.apply(games).map(\.id), ["2"])
    XCTAssertEqual(GameFilter.local.apply(games).map(\.id), ["1", "3"])
  }
}
