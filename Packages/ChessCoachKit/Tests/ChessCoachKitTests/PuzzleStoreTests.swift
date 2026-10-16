import GRDB
import XCTest
@testable import ChessCoachKit

final class PuzzleStoreTests: XCTestCase {
  var path: String!

  override func setUpWithError() throws {
    path = FileManager.default.temporaryDirectory
      .appendingPathComponent("puzzles-\(UUID().uuidString).sqlite").path
    let db = try DatabaseQueue(path: path)
    try db.write { db in
      try db.execute(sql: """
        CREATE TABLE puzzle(id TEXT PRIMARY KEY, fen TEXT, moves TEXT, rating INT, rd INT,
          popularity INT, plays INT, themes TEXT, primaryTheme TEXT, opening TEXT);
        CREATE TABLE puzzle_theme(puzzleId TEXT, theme TEXT, rating INT);
        CREATE INDEX puzzle_theme_theme_rating ON puzzle_theme(theme, rating);
        """)
      let rows: [(String, Int, Int, String, String, String?)] = [
        ("p1", 800, 95, "fork short", "fork", "Italian_Game"),
        ("p2", 850, 99, "mate mateIn1 oneMove", "mateIn1", nil),
        ("p3", 900, 90, "fork pin", "fork", nil),
        ("p4", 1300, 97, "fork", "fork", nil),
        ("p5", 1450, 88, "backRankMate mate mateIn1", "backRankMate", nil),
      ]
      for (id, rating, pop, themes, primary, opening) in rows {
        try db.execute(
          sql: "INSERT INTO puzzle VALUES (?, ?, ?, ?, 75, ?, 500, ?, ?, ?)",
          arguments: [id, "8/8/8/8/8/8/8/K6k w - - 0 1", "a1a2 h1h2", rating, pop, themes, primary, opening])
        for t in themes.split(separator: " ") {
          try db.execute(sql: "INSERT INTO puzzle_theme VALUES (?, ?, ?)", arguments: [id, String(t), rating])
        }
      }
    }
    try db.close()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(atPath: path)
  }

  func test_givenFixture_whenPuzzleById_thenDecodesAllFields() throws {
    let p = try XCTUnwrap(PuzzleStore(path: path).puzzle(id: "p1"))
    XCTAssertEqual(
      p,
      Puzzle(
        id: "p1", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2", "h1h2"], rating: 800, rd: 75,
        popularity: 95, themes: ["fork", "short"], primaryTheme: "fork", opening: "Italian_Game"))
    XCTAssertNil(try PuzzleStore(path: path).puzzle(id: "nope"))
  }

  func test_givenThemeAndRating_whenQueried_thenReturnsInWindowByPopularity() throws {
    let found = try PuzzleStore(path: path).puzzles(theme: "fork", around: 850, limit: 2)
    XCTAssertEqual(found.map(\.id), ["p1", "p3"])
  }

  func test_givenTooFewInWindow_whenQueried_thenWidensUpTo600() throws {
    let store = try PuzzleStore(path: path)
    XCTAssertEqual(try store.puzzles(theme: "fork", around: 850, limit: 3).map(\.id), ["p4", "p1", "p3"])
    XCTAssertEqual(try store.puzzles(theme: nil, around: 400, limit: 10).count, 3)  // ±600 stops at 1000
  }

  func test_givenExcludedIds_whenQueried_thenSkipsThem() throws {
    let found = try PuzzleStore(path: path).puzzles(theme: nil, around: 850, excluding: ["p2"], limit: 2)
    XCTAssertEqual(found.map(\.id), ["p1", "p3"])
  }

  func test_givenFixture_whenCountingThemes_thenCountsSecondaryTagsToo() throws {
    let store = try PuzzleStore(path: path)
    XCTAssertEqual(try store.count(theme: "fork"), 3)
    XCTAssertEqual(try store.count(theme: "mateIn1"), 2)
    XCTAssertEqual(try store.count(theme: nil), 5)
    XCTAssertEqual(try store.themes().first?.theme, "fork")
  }

  func test_givenMissingBundle_whenBundled_thenNil() {
    XCTAssertNil(PuzzleStore.bundled(in: Bundle(for: Self.self)))
  }

  func test_givenRealBundle_whenInspected_thenHasCoverageForBeginnerThemes() throws {
    let real = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("ChessCoach/Resources/puzzles.sqlite").path
    guard FileManager.default.fileExists(atPath: real) else { throw XCTSkip("bundle not built") }
    XCTAssertGreaterThan(try PuzzleStore(path: real).count(theme: nil), 40_000)
    var config = Configuration()
    config.readonly = true
    let db = try DatabaseQueue(path: real, configuration: config)
    for theme in ["mateIn1", "fork", "hangingPiece", "backRankMate"] {
      let n = try db.read {
        try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM puzzle_theme WHERE theme = ? AND rating < 1200",
                         arguments: [theme]) ?? 0
      }
      XCTAssertGreaterThan(n, 300, theme)
    }
  }
}
