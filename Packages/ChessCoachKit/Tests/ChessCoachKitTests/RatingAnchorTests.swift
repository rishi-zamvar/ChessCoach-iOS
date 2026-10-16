import XCTest
@testable import ChessCoachKit

final class RatingAnchorTests: XCTestCase {
  func game(_ i: Int, elo: Int, color: String = "white", timeClass: String = "rapid", source: GameRecord.Source = .chesscom) -> GameRecord {
    GameRecord(
      id: "g\(i)", source: source, pgn: "", white: "a", black: "b", userColor: color, result: "1-0", termination: "",
      timeControl: "600", opponentKind: "human", startedAt: Date(timeIntervalSince1970: Double(i) * 1000),
      endedAt: Date(timeIntervalSince1970: Double(i) * 1000 + 600),
      whiteElo: color == "white" ? elo : 1500, blackElo: color == "black" ? elo : 1500, timeClass: timeClass)
  }

  func test_givenRecentGames_whenAnchored_thenMedianOfOwnRatingInLatestTimeClass() {
    let games = [game(1, elo: 650), game(2, elo: 700, color: "black"), game(3, elo: 720), game(4, elo: 1200, timeClass: "bullet"),
                 game(5, elo: 690), game(0, elo: 900, source: .local)]
    // Latest game (5) is rapid: rapid ratings 650, 700, 720, 690 → median 695.
    XCTAssertEqual(RatingAnchor.realRating(games), 695)
  }

  func test_givenNoChessComGames_whenAnchored_thenNil() {
    XCTAssertNil(RatingAnchor.realRating([game(1, elo: 700, source: .local)]))
  }

  func test_givenPlacementFarAboveReal_whenBlended_thenCappedNearReal() {
    XCTAssertEqual(RatingAnchor.blend(placement: 1300, real: 700), 800)
    XCTAssertEqual(RatingAnchor.blend(placement: 650, real: 700), 650)
    XCTAssertEqual(RatingAnchor.blend(placement: 1300, real: nil), 1300)
  }

  func test_givenDriftedRating_whenChecked_thenRecalibrateOnlyBeyond150() {
    XCTAssertTrue(RatingAnchor.needsRecalibration(current: 1100, real: 700))
    XCTAssertFalse(RatingAnchor.needsRecalibration(current: 800, real: 700))
    XCTAssertFalse(RatingAnchor.needsRecalibration(current: 1100, real: nil))
  }
}
