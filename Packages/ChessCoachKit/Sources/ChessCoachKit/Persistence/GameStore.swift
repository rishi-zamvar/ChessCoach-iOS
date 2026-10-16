import Foundation
import GRDB

/// Saves and lists finished games.
public struct GameStore: Sendable {
  let database: AppDatabase

  public init(database: AppDatabase) {
    self.database = database
  }

  public func save(_ game: GameRecord) throws {
    try database.writer.write { try game.save($0) }
  }

  public func recent(limit: Int = 50) throws -> [GameRecord] {
    try database.reader.read { db in
      try GameRecord.order(Column("endedAt").desc).limit(limit).fetchAll(db)
    }
  }

  public func ids(source: GameRecord.Source) throws -> Set<String> {
    try database.reader.read { db in
      Set(try String.fetchAll(db, sql: "SELECT id FROM game WHERE source = ?", arguments: [source.rawValue]))
    }
  }

  /// Inserts games not already stored; returns how many were new.
  @discardableResult
  public func insertNew(_ games: [GameRecord]) throws -> Int {
    try database.writer.write { db in
      var inserted = 0
      for game in games where try !game.exists(db) {
        try game.insert(db)
        inserted += 1
      }
      return inserted
    }
  }

  public func game(id: String) throws -> GameRecord? {
    try database.reader.read { try GameRecord.fetchOne($0, key: id) }
  }
}
