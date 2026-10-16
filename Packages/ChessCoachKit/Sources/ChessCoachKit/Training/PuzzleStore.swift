import Foundation
import GRDB

/// One Lichess puzzle. `fen` is the position BEFORE the opponent's setup move `moves[0]`;
/// the user then plays `moves[1]`, `moves[3]`, ... (all UCI).
public struct Puzzle: Sendable, Equatable, Codable, Identifiable {
  public var id: String
  public var fen: String
  public var moves: [String]
  public var rating: Int
  public var rd: Int
  public var popularity: Int
  public var themes: [String]
  public var primaryTheme: String
  public var opening: String?

  public init(
    id: String, fen: String, moves: [String], rating: Int, rd: Int, popularity: Int,
    themes: [String], primaryTheme: String, opening: String?
  ) {
    self.id = id
    self.fen = fen
    self.moves = moves
    self.rating = rating
    self.rd = rd
    self.popularity = popularity
    self.themes = themes
    self.primaryTheme = primaryTheme
    self.opening = opening
  }
}

extension Puzzle: FetchableRecord {
  public init(row: Row) {
    self.init(
      id: row["id"], fen: row["fen"],
      moves: (row["moves"] as String).split(separator: " ").map(String.init),
      rating: row["rating"], rd: row["rd"], popularity: row["popularity"],
      themes: (row["themes"] as String).split(separator: " ").map(String.init),
      primaryTheme: row["primaryTheme"], opening: row["opening"])
  }
}

/// Read-only access to the bundled puzzle database built by `scripts/build_puzzles.py`.
public final class PuzzleStore: Sendable {
  private let dbQueue: DatabaseQueue

  public init(path: String) throws {
    var config = Configuration()
    config.readonly = true
    dbQueue = try DatabaseQueue(path: path, configuration: config)
  }

  public static func bundled(in bundle: Bundle = .main) -> PuzzleStore? {
    guard let url = bundle.url(forResource: "puzzles", withExtension: "sqlite") else { return nil }
    return try? PuzzleStore(path: url.path)
  }

  /// Puzzles near `rating`, widening the window in ±100 steps (up to ±600) until `limit` are found.
  /// Ordered by popularity, then a deterministic id-derived shuffle.
  public func puzzles(
    theme: String?, around rating: Int, window: Int = 100, excluding: Set<String> = [], limit: Int
  ) throws -> [Puzzle] {
    let excluded = Array(excluding)
    return try dbQueue.read { db in
      var w = max(window, 0)
      while true {
        let lo = rating - w, hi = rating + w
        let request: SQLRequest<Puzzle> =
          if let theme {
            """
            SELECT p.* FROM puzzle_theme t JOIN puzzle p ON p.id = t.puzzleId
            WHERE t.theme = \(theme) AND t.rating BETWEEN \(lo) AND \(hi) AND p.id NOT IN \(excluded)
            ORDER BY p.popularity DESC, substr(p.id, 2) LIMIT \(limit)
            """
          } else {
            """
            SELECT * FROM puzzle
            WHERE rating BETWEEN \(lo) AND \(hi) AND id NOT IN \(excluded)
            ORDER BY popularity DESC, substr(id, 2) LIMIT \(limit)
            """
          }
        let found = try request.fetchAll(db)
        if found.count >= limit || w >= 600 { return found }
        w = min(w + 100, 600)
      }
    }
  }

  public func puzzle(id: String) throws -> Puzzle? {
    try dbQueue.read { db in
      try SQLRequest<Puzzle>("SELECT * FROM puzzle WHERE id = \(id)").fetchOne(db)
    }
  }

  /// Number of puzzles carrying `theme` (any position in its tag list); nil counts all puzzles.
  public func count(theme: String?) throws -> Int {
    try dbQueue.read { db in
      let request: SQLRequest<Int> =
        if let theme { "SELECT COUNT(*) FROM puzzle_theme WHERE theme = \(theme)" }
        else { "SELECT COUNT(*) FROM puzzle" }
      return try request.fetchOne(db) ?? 0
    }
  }

  /// Every theme with its puzzle count, most common first.
  public func themes() throws -> [(theme: String, count: Int)] {
    try dbQueue.read { db in
      try Row.fetchAll(
        db, sql: "SELECT theme, COUNT(*) AS n FROM puzzle_theme GROUP BY theme ORDER BY n DESC, theme"
      ).map { (theme: $0["theme"], count: $0["n"]) }
    }
  }
}
