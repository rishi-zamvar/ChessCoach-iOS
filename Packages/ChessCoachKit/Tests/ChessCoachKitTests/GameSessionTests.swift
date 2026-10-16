import ChessKit
import XCTest
@testable import ChessCoachKit

final class GameSessionTests: XCTestCase {
  @discardableResult
  func play(_ session: inout GameSession, _ moves: [String]) -> [PlayedMove] {
    moves.map { uci in
      guard case .applied(let played) = session.apply(uci: uci) else {
        XCTFail("could not apply \(uci)")
        fatalError()
      }
      return played
    }
  }

  func test_givenStartPosition_whenAskingLegalTargetsOfE2_thenE3AndE4() {
    let session = GameSession()
    XCTAssertEqual(Set(session.legalTargets(from: Square("e2"))), [Square("e3"), Square("e4")])
  }

  func test_givenStartPosition_whenOpponentPieceQueried_thenNoTargetsForWrongSide() {
    let session = GameSession()
    XCTAssertEqual(session.legalTargets(from: Square("e7")), [])
  }

  func test_givenScholarsMate_whenPlayed_thenCheckmateAndWhiteWins() {
    var session = GameSession()
    let moves = play(&session, ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"])
    XCTAssertEqual(moves.last?.san, "Qxf7#")
    XCTAssertEqual(session.result?.winner, .white)
    XCTAssertEqual(session.result?.termination, .checkmate)
    XCTAssertEqual(session.result?.pgnResult, "1-0")
    XCTAssertTrue(session.isOver)
  }

  func test_givenIllegalMove_whenApplied_thenRejectedAndNothingChanges() {
    var session = GameSession()
    XCTAssertEqual(session.apply(from: Square("e2"), to: Square("e5")), .illegal)
    XCTAssertEqual(session.history.count, 0)
    XCTAssertEqual(session.sideToMove, .white)
  }

  func test_givenPawnOnSeventh_whenMovedWithoutPiece_thenNeedsPromotionThenPromotes() {
    var session = GameSession(startFEN: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
    XCTAssertEqual(session.apply(from: Square("e7"), to: Square("e8")), .needsPromotion)
    XCTAssertEqual(session.history.count, 0)
    guard case .applied(let played) = session.apply(from: Square("e7"), to: Square("e8"), promotion: .queen) else {
      return XCTFail("promotion not applied")
    }
    XCTAssertTrue(played.san.hasPrefix("e8=Q"), played.san)
    XCTAssertEqual(played.uci, "e7e8q")
    XCTAssertEqual(session.position.piece(at: Square("e8"))?.kind, .queen)
  }

  func test_givenEngineUCIWithPromotion_whenApplied_thenPromotes() {
    var session = GameSession(startFEN: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1")
    guard case .applied(let played) = session.apply(uci: "e7e8n") else { return XCTFail() }
    XCTAssertTrue(played.san.hasPrefix("e8=N"))
  }

  func test_givenCastlingRights_whenKingCastles_thenSANIsOO() {
    var session = GameSession()
    let moves = play(&session, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1"])
    XCTAssertEqual(moves.last?.san, "O-O")
    XCTAssertEqual(session.position.piece(at: Square("f1"))?.kind, .rook)
  }

  func test_givenStalematePosition_whenMoveCreatesStalemate_thenDraw() {
    // White Qc7?? stalemates the black king on a8... use a known stalemate: Kb6, Qc6 vs Ka8 after Qc7.
    var session = GameSession(startFEN: "k7/8/1K6/8/8/8/8/2Q5 w - - 0 1")
    play(&session, ["c1c7"])
    XCTAssertEqual(session.result?.termination, .stalemate)
    XCTAssertNil(session.result?.winner)
    XCTAssertEqual(session.result?.pgnResult, "1/2-1/2")
  }

  func test_givenPlayedGame_whenPGNExported_thenParsesBackWithSameMovesAndClocks() throws {
    var session = GameSession()
    play(&session, ["e2e4", "e7e5", "g1f3"])
    session.setClockAfterLastMove(595.4)
    let pgn = session.pgn(tags: ["White": "You", "Black": "Maia 1100", "Event": "ChessCoach"])
    XCTAssertTrue(pgn.contains("[White \"You\"]"))
    XCTAssertTrue(pgn.contains("{[%clk 0:09:55]}"), pgn)
    XCTAssertTrue(pgn.hasSuffix("*"), pgn)
    let parsed = try Game(pgn: pgn)
    XCTAssertEqual(parsed.positions.count, 4)  // start + 3 plies
  }

  func test_givenCapture_whenMaterialComputed_thenCapturedListAndBalance() {
    var session = GameSession()
    play(&session, ["e2e4", "d7d5", "e4d5"])
    XCTAssertEqual(session.captured(by: .white).map(\.kind), [.pawn])
    XCTAssertEqual(session.captured(by: .black), [])
    XCTAssertEqual(session.materialBalance, 1)
  }

  func test_givenGameInProgress_whenWhiteResigns_thenBlackWins() {
    var session = GameSession()
    session.resign(.white)
    XCTAssertEqual(session.result, GameResult(winner: .black, termination: .resignation))
    XCTAssertEqual(session.apply(uci: "e2e4"), .illegal)
  }

  func test_givenOpponentHasOnlyKing_whenWhiteFlags_thenDrawByInsufficientMaterial() {
    var session = GameSession(startFEN: "k7/8/8/8/8/8/8/KQ6 w - - 0 1")
    session.flag(.white)
    XCTAssertEqual(session.result, GameResult(winner: nil, termination: .timeoutVsInsufficientMaterial))
  }

  func test_givenOpponentHasMaterial_whenWhiteFlags_thenBlackWins() {
    var session = GameSession()
    session.flag(.white)
    XCTAssertEqual(session.result, GameResult(winner: .black, termination: .timeout))
  }

  func test_givenFiveMoves_whenPositionAtPly_thenMatchesHistory() {
    var session = GameSession()
    let moves = play(&session, ["e2e4", "e7e5", "g1f3"])
    XCTAssertEqual(session.fen(atPly: 0), GameSession.standardFEN)
    XCTAssertEqual(session.fen(atPly: 2), moves[1].fenAfter)
    XCTAssertEqual(session.fen(atPly: 3), session.position.fen)
  }
}

final class GameSessionRegressionTests: XCTestCase {
  func test_givenOpponentBoxedInButSideToMoveHasMoves_whenLoaded_thenNotOver() {
    // White to mate in one; Black (not to move) has no legal moves. Not a stalemate.
    var session = GameSession(startFEN: "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1")
    XCTAssertNil(session.result)
    XCTAssertFalse(session.legalTargets(from: Square("f7")).isEmpty)
    guard case .applied(let played) = session.apply(uci: "f7g7") else { return XCTFail() }
    XCTAssertEqual(played.san, "Qg7#")
    XCTAssertEqual(session.result?.termination, .checkmate)
  }

  func test_givenCheckmatedSideToMove_whenLoaded_thenCheckmate() {
    let session = GameSession(startFEN: "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")
    XCTAssertEqual(session.result, GameResult(winner: .white, termination: .checkmate))
  }

  func test_givenStalematedSideToMove_whenLoaded_thenStalemate() {
    let session = GameSession(startFEN: "k7/2Q5/1K6/8/8/8/8/8 b - - 0 1")
    XCTAssertEqual(session.result?.termination, .stalemate)
  }

  func test_givenQuoteInPlayerName_whenPGNExported_thenEscaped() {
    let pgn = GameSession().pgn(tags: ["White": "A \"B\" C"])
    XCTAssertTrue(pgn.contains(#"[White "A \"B\" C"]"#), pgn)
  }
}
