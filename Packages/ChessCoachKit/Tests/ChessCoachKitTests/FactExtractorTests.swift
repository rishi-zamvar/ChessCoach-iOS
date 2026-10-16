import ChessKit
import XCTest
@testable import ChessCoachKit

final class FactExtractorTests: XCTestCase {
  func motifs(_ fen: String, _ uci: String, file: StaticString = #filePath, line: UInt = #line) -> [Motif] {
    guard let facts = FactExtractor.moveFacts(fen: fen, uci: uci) else {
      XCTFail("move \(uci) not legal in \(fen)", file: file, line: line)
      return []
    }
    return facts.motifs
  }

  func test_givenKnightJumpHittingKingAndRook_whenAnalyzed_thenForkWithCheck() {
    let facts = FactExtractor.moveFacts(fen: "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1", uci: "d5c7")!
    XCTAssertTrue(facts.motifs.contains(.fork), "\(facts.motifs)")
    XCTAssertTrue(facts.motifs.contains(.check))
    XCTAssertEqual(Set(facts.targets.map(\.square)), ["e8", "a8"])
  }

  func test_givenBishopLiningUpKnightAndKing_whenAnalyzed_thenPin() {
    XCTAssertTrue(motifs("4k3/3n4/8/8/8/8/8/4KB2 w - - 0 1", "f1b5").contains(.pin))
  }

  func test_givenRookCheckWithQueenBehindKing_whenAnalyzed_thenSkewer() {
    let m = motifs("8/q3k3/8/8/8/8/8/4K2R w - - 0 1", "h1h7")
    XCTAssertTrue(m.contains(.skewer), "\(m)")
    XCTAssertTrue(m.contains(.check))
  }

  func test_givenRookToBackRankBehindPawns_whenAnalyzed_thenBackRankMate() {
    let m = motifs("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", "d1d8")
    XCTAssertTrue(m.contains(.mate))
    XCTAssertTrue(m.contains(.backRankMate))
  }

  func test_givenQuietQueenMoveEyeingBackRank_whenAnalyzed_thenMateThreat() {
    let m = motifs("6k1/5ppp/8/8/8/8/5PPP/3Q2K1 w - - 0 1", "d1a4")
    XCTAssertTrue(m.contains(.mateThreat), "\(m)")
    XCTAssertFalse(m.contains(.check))
  }

  func test_givenQuietMove_whenAnalyzed_thenNoMateThreat() {
    XCTAssertFalse(motifs(GameSession.standardFEN, "e2e4").contains(.mateThreat))
  }

  func test_givenKnightUncoveringRookOnQueen_whenAnalyzed_thenDiscoveredAttack() {
    XCTAssertTrue(motifs("4k3/4q3/8/8/4N3/8/8/4RK2 w - - 0 1", "e4c5").contains(.discoveredAttack))
  }

  func test_givenCaptureOfUndefendedKnight_whenAnalyzed_thenWinsMaterialAndHangingPiece() {
    let facts = FactExtractor.moveFacts(fen: "4k3/8/8/3n4/8/8/8/3QK3 w - - 0 1", uci: "d1d5")!
    XCTAssertEqual(facts.materialWon, 3)
    XCTAssertTrue(facts.motifs.contains(.winsMaterial))
    XCTAssertTrue(facts.motifs.contains(.hangingPiece))
  }

  func test_givenQueenTakesDefendedPawn_whenAnalyzed_thenNoMaterialWon() {
    let facts = FactExtractor.moveFacts(fen: "4k3/3p4/4p3/8/8/8/8/4QK2 w - - 0 1", uci: "e1e6")!
    XCTAssertEqual(facts.materialWon, 0)
    XCTAssertFalse(facts.motifs.contains(.winsMaterial))
  }

  func test_givenAttackedUndefendedKnight_whenHangingPiecesListed_thenIncluded() {
    let hanging = FactExtractor.hangingPieces(fen: "4k3/8/4p3/3N4/8/8/8/4K3 w - - 0 1", of: .white)
    XCTAssertEqual(hanging.map(\.square), [Square("d5")])
  }

  func test_givenStartPosition_whenHangingPiecesListed_thenNone() {
    XCTAssertTrue(FactExtractor.hangingPieces(fen: GameSession.standardFEN, of: .white).isEmpty)
  }

  func test_givenExchangeSequences_whenSEE_thenNetGain() {
    let undefended = BoardMap(Position(fen: "4k3/8/8/3n4/8/8/8/3QK3 w - - 0 1")!)
    XCTAssertEqual(StaticExchange.evaluate(undefended, square: Square("d5"), by: .white), 3)
    let defendedPawn = BoardMap(Position(fen: "4k3/3p4/4p3/8/8/8/8/4QK2 w - - 0 1")!)
    XCTAssertEqual(StaticExchange.evaluate(defendedPawn, square: Square("e6"), by: .white), 0)
    // Pawn takes a knight defended by a pawn: +3 -1 = +2.
    let pawnTakesKnight = BoardMap(Position(fen: "4k3/2p5/3n4/4P3/8/8/8/4K3 w - - 0 1")!)
    XCTAssertEqual(StaticExchange.evaluate(pawnTakesKnight, square: Square("d6"), by: .white), 2)
  }

  func test_givenUCILine_whenConvertedToSAN_thenReadable() {
    XCTAssertEqual(FactExtractor.sanLine(fen: GameSession.standardFEN, ucis: ["e2e4", "e7e5", "g1f3", "zzzz"]), ["e4", "e5", "Nf3"])
  }

  func test_givenPositions_whenPhaseAsked_thenOpeningMiddlegameEndgame() {
    XCTAssertEqual(FactExtractor.phase(fen: GameSession.standardFEN, ply: 0), .opening)
    XCTAssertEqual(FactExtractor.phase(fen: GameSession.standardFEN, ply: 30), .middlegame)
    XCTAssertEqual(FactExtractor.phase(fen: "8/8/4k3/8/8/8/3PK3/7R w - - 0 1", ply: 60), .endgame)
  }

  func test_givenQueenBlunder_whenSheetBuilt_thenHangingQueenAndPunishLine() {
    // 1.e4 e5 2.Qh5 Nc6 3.Qxf7+?? is fine; use 2.Qg4?? d5 where ...Bxg4 wins the queen.
    let fen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"
    let sheet = FactExtractor.sheet(fen: fen, played: "d1g4", bestLine: ["g1f3", "b8c6"], punishLine: ["d7d5", "g4g3"], ply: 2)!
    XCTAssertEqual(sheet.played.san, "Qg4")
    XCTAssertEqual(sheet.best?.san, "Nf3")
    XCTAssertEqual(sheet.punishLineSAN.first, "d5")
    XCTAssertEqual(sheet.mover, "white")
    XCTAssertEqual(sheet.phase, .opening)
    XCTAssertTrue(sheet.vocabulary.isSuperset(of: ["Qg4", "Nf3", "d5"]))
  }

  func test_givenQueenLeftEnPrise_whenSheetBuilt_thenHangingAfterListsQueen() {
    // White queen to h5 where the g6 pawn... use a clean case: Qd1-d5 into a pawn attack from e6.
    let sheet = FactExtractor.sheet(fen: "4k3/8/4p3/8/8/8/8/3QK3 w - - 0 1", played: "d1d5", bestLine: ["d1d7"], punishLine: ["e6d5"], ply: 40)!
    XCTAssertEqual(sheet.hangingAfter.first?.kind, "queen")
    XCTAssertEqual(sheet.hangingAfter.first?.square, "d5")
    XCTAssertEqual(sheet.punish?.materialWon, 9)
  }
}
