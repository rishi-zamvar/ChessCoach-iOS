import XCTest
@testable import ChessCoachKit

final class WinChanceTests: XCTestCase {
  func test_givenCentipawns_whenConverted_thenMatchesLichessCurve() {
    XCTAssertEqual(WinChance.winPercent(.centipawns(0)), 50, accuracy: 1e-9)
    XCTAssertEqual(WinChance.winPercent(.centipawns(100)), 59.10258971916128, accuracy: 1e-9)
    XCTAssertEqual(WinChance.winPercent(.centipawns(-300)), 24.88744990616516, accuracy: 1e-9)
  }

  func test_givenHugeCentipawns_whenConverted_thenClampedAt1000() {
    XCTAssertEqual(WinChance.winPercent(.centipawns(5000)), 97.54474363414323, accuracy: 1e-9)
    XCTAssertEqual(WinChance.winPercent(.centipawns(5000)), WinChance.winPercent(.centipawns(1000)))
  }

  func test_givenMateScores_whenConverted_thenCertainWinOrLoss() {
    XCTAssertEqual(WinChance.winPercent(.mate(3)), 100)
    XCTAssertEqual(WinChance.winPercent(.mate(-2)), 0)
  }

  func test_givenWinDrops_whenAccuracyComputed_thenMatchesFormula() {
    XCTAssertEqual(WinChance.moveAccuracy(winBefore: 60, winAfter: 50), 64.57982845372067, accuracy: 1e-9)
    XCTAssertEqual(WinChance.moveAccuracy(winBefore: 80, winAfter: 20), 5.399328234910814, accuracy: 1e-9)
    XCTAssertEqual(WinChance.moveAccuracy(winBefore: 50, winAfter: 50), 100)
    XCTAssertEqual(WinChance.moveAccuracy(winBefore: 40, winAfter: 55), 100)
  }

  func test_givenFlawlessGame_whenGameAccuracy_thenBothNear100() {
    let flat = Array(repeating: 50.0, count: 41)
    let result = WinChance.gameAccuracy(whiteWinPercents: flat)
    XCTAssertEqual(result.white ?? 0, 100, accuracy: 0.01)
    XCTAssertEqual(result.black ?? 0, 100, accuracy: 0.01)
  }

  func test_givenWhiteBlunders_whenGameAccuracy_thenWhiteLowerThanBlack() {
    // Ply index 4 (White's 3rd move) drops White from 50 to 10; Black plays perfectly.
    var w = Array(repeating: 50.0, count: 5)
    w += Array(repeating: 10.0, count: 15)
    let result = WinChance.gameAccuracy(whiteWinPercents: w)
    XCTAssertLessThan(result.white!, result.black!)
    XCTAssertEqual(result.black ?? 0, 100, accuracy: 0.01)
    XCTAssertLessThan(result.white!, 90)
  }

  func test_givenTooFewPlies_whenGameAccuracy_thenNil() {
    XCTAssertNil(WinChance.gameAccuracy(whiteWinPercents: [50]).white)
  }

  func test_givenOnlyWhiteMoved_whenGameAccuracy_thenBlackNil() {
    let result = WinChance.gameAccuracy(whiteWinPercents: [50, 52])
    XCTAssertNotNil(result.white)
    XCTAssertNil(result.black)
  }
}
