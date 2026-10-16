import XCTest
@testable import ChessCoachKit

final class MoveClassifierTests: XCTestCase {
  func eval(
    best: Double = 0.55, second: Double? = 0.53, played: Double, isBest: Bool = false, legal: Int = 30,
    book: Bool = false, sacrifice: Bool = false, maia: Double? = nil, gift: Double? = nil
  ) -> PlyEval {
    PlyEval(
      legalMoveCount: legal, isBook: book, bestEP: best, secondBestEP: second, playedEP: played,
      playedIsBest: isBest, isSacrifice: sacrifice, maiaProbability: maia, opponentPreviousLoss: gift)
  }

  func test_givenOnlyOneLegalMove_whenClassified_thenForced() {
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.1, legal: 1)), .forced)
  }

  func test_givenBookPosition_whenClassified_thenBook() {
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.5, book: true)), .book)
  }

  func test_givenLossBands_whenClassified_thenLadderMatchesThresholds() {
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.55, isBest: true)), .best)
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.54)), .excellent)
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.51)), .good)
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.47)), .inaccuracy)
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.40)), .mistake)
    XCTAssertEqual(MoveClassifier.classify(eval(played: 0.20)), .blunder)
  }

  func test_givenExactBoundaries_whenClassified_thenInclusiveUpperBounds() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.60, second: nil, played: 0.58)), .excellent)
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.60, second: nil, played: 0.50)), .inaccuracy)
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.60, second: nil, played: 0.40)), .mistake)
  }

  func test_givenOnlyMoveThatKeepsTheWin_whenPlayed_thenGreat() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.85, second: 0.45, played: 0.85, isBest: true)), .great)
  }

  func test_givenOnlyMoveThatPunishesABlunder_whenPlayed_thenBestNotGreat() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 1.0, second: 0.5, played: 1.0, isBest: true, gift: 0.5)), .best)
  }

  func test_givenBestButAlternativesSimilar_whenPlayed_thenJustBest() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.85, second: 0.80, played: 0.85, isBest: true)), .best)
  }

  func test_givenSoundSacrificeHumansRarelyFind_whenPlayed_thenBrilliant() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.7, played: 0.7, isBest: true, sacrifice: true, maia: 0.04)), .brilliant)
  }

  func test_givenSacrificeHumansFindEasily_whenPlayed_thenNotBrilliant() {
    XCTAssertNotEqual(MoveClassifier.classify(eval(best: 0.7, played: 0.7, isBest: true, sacrifice: true, maia: 0.4)), .brilliant)
  }

  func test_givenSacrificeWithoutMaiaData_whenPlayed_thenNotBrilliant() {
    XCTAssertNotEqual(MoveClassifier.classify(eval(best: 0.7, played: 0.7, isBest: true, sacrifice: true)), .brilliant)
  }

  func test_givenLosingSacrifice_whenPlayed_thenNotBrilliant() {
    XCTAssertNotEqual(MoveClassifier.classify(eval(best: 0.3, played: 0.3, isBest: true, sacrifice: true, maia: 0.01)), .brilliant)
  }

  func test_givenOpponentBlunderedAndUserDidNotPunish_whenClassified_thenMiss() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.85, second: 0.6, played: 0.55, gift: 0.35)), .miss)
  }

  func test_givenOpponentBlunderedAndUserPunished_whenClassified_thenNotMiss() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.85, second: 0.84, played: 0.84, gift: 0.35)), .excellent)
  }

  func test_givenAlreadyLostPosition_whenBigDrop_thenCappedAtInaccuracy() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.04, second: nil, played: 0.0)), .good)
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.04, second: nil, played: 0.0, gift: nil)).isError, false)
  }

  func test_givenWinningPositionThrownToLosing_whenClassified_thenStillBlunder() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.97, second: nil, played: 0.2)), .blunder)
  }

  func test_givenWinningPositionStillWinningAfterSlip_whenClassified_thenInaccuracy() {
    XCTAssertEqual(MoveClassifier.classify(eval(best: 0.99, second: nil, played: 0.7)), .inaccuracy)
  }

  func test_givenLabels_whenAsked_thenCriticalSetAndGlyphs() {
    XCTAssertTrue(MoveClass.blunder.isCritical)
    XCTAssertFalse(MoveClass.good.isCritical)
    XCTAssertEqual(MoveClass.blunder.glyph, "??")
    XCTAssertEqual(Set(MoveClass.allCases.map(\.glyph)).count, MoveClass.allCases.count)
  }
}
