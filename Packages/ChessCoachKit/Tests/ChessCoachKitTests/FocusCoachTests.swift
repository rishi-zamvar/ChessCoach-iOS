import ChessKit
import XCTest
@testable import ChessCoachKit

final class FocusCoachTests: XCTestCase {
  let backRankFEN = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
  let looseBishopFEN = "4k3/8/8/3b4/8/8/8/3RK3 w - - 0 1"
  let forkFEN = "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1"

  func test_givenTallies_whenPickingFocus_thenBiggestWeaknessThenPuzzlesThenFreePieces() {
    XCTAssertEqual(WeaknessTally(hung: 2, missedFree: 1).focus(), .hangingOwn)
    XCTAssertEqual(WeaknessTally().focus(puzzleRatings: ["B1": 500, "C1": 900, "C2": 800]), .mates)
    XCTAssertEqual(WeaknessTally().focus(), .freePieces)
    XCTAssertEqual(WeaknessTally(hung: 10).adding(WeaknessTally(missedMate: 1)).hung, 7, accuracy: 1e-9)
  }

  func test_givenPositions_whenScanning_thenFindsMateFreePieceAndFork() {
    XCTAssertEqual(BoardScan.mateInOne(fen: backRankFEN), "a1a8")
    XCTAssertEqual(BoardScan.freeCapture(fen: looseBishopFEN)?.uci, "d1d5")
    XCTAssertEqual(BoardScan.tactic(fen: forkFEN)?.uci, "d5c7")
    XCTAssertNil(BoardScan.mateInOne(fen: forkFEN))
  }

  func test_givenFocus_whenBotLooksForGifts_thenEachSetsUpThatLesson() {
    let looseKnight = "4k3/8/2n5/8/8/8/8/3QK3 b - - 0 1"
    let freeGifts = BoardScan.gifts(fen: looseKnight, focus: .freePieces)
    XCTAssertFalse(freeGifts.isEmpty)
    let mateRook = "2r3k1/5ppp/8/8/8/8/8/R5K1 b - - 0 1"
    let mateGifts = BoardScan.gifts(fen: mateRook, focus: .mates)
    XCTAssertFalse(mateGifts.isEmpty)
    for uci in mateGifts {
      var s = GameSession(startFEN: mateRook)
      s.apply(uci: uci)
      XCTAssertNotNil(BoardScan.mateInOne(fen: s.position.fen), uci)
    }
    XCTAssertTrue(BoardScan.gifts(fen: looseKnight, focus: .hangingOwn).isEmpty)
  }

  func test_givenSlips_whenCheckingHoldUp_thenRulesFireInOrder() {
    let hung = HoldUp.check(fenBefore: "4k3/8/4p3/8/8/2N5/8/4K3 w - - 0 1", played: "c3d5", label: .mistake, focus: nil)
    XCTAssertEqual(hung?.kind, .hungPiece)
    XCTAssertEqual(hung?.line, "Hold up. Your knight on d5 has no defender.")
    XCTAssertEqual(hung?.marks[Square("d5")], .red)

    XCTAssertEqual(HoldUp.check(fenBefore: backRankFEN, played: "g1f1", label: .good, focus: nil)?.kind, .missedMate)
    XCTAssertNil(HoldUp.check(fenBefore: backRankFEN, played: "a1a8", label: .best, focus: nil))

    let free = HoldUp.check(fenBefore: looseBishopFEN, played: "e1e2", label: .mistake, focus: nil)
    XCTAssertEqual(free?.kind, .missedFree)
    XCTAssertEqual(free?.marks[Square("d5")], .green)
    XCTAssertNil(HoldUp.check(fenBefore: looseBishopFEN, played: "d1d5", label: .best, focus: nil))
  }

  func test_givenCandidates_whenChoosing_thenNoMercyThenFocusGiftThenNormal() {
    typealias C = TeachingBot.Candidate
    // White's knight on d5 is loose; black to move.
    let fen = "4k3/8/4p3/3N4/8/8/8/4K3 b - - 0 1"
    let take = C(uci: "e6d5", san: "exd5", ep: 0.8, maiaProbability: 0.3)
    let quiet = C(uci: "e8d7", san: "Kd7", ep: 0.5, maiaProbability: 0.5)
    var gift = C(uci: "e8f7", san: "Kf7", ep: 0.45, maiaProbability: 0.1)
    gift.isGift = true
    XCTAssertEqual(TeachingBot.choices([take, quiet, gift], fen: fen, best: 0.8, focus: .freePieces, giftDue: true).map(\.uci), ["e6d5"])
    let calm = "4k3/8/4p3/8/8/8/8/4K3 b - - 0 1"
    XCTAssertEqual(TeachingBot.choices([quiet, gift], fen: calm, best: 0.5, focus: .freePieces, giftDue: true).map(\.uci), ["e8f7"])
    XCTAssertEqual(TeachingBot.choices([quiet, gift], fen: calm, best: 0.5, focus: .freePieces, giftDue: false).map(\.uci), ["e8d7"])
  }
}
