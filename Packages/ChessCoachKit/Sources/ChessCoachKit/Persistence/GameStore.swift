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

  public func game(id: String) throws -> GameRecord? {
    try database.reader.read { try GameRecord.fetchOne($0, key: id) }
  }
}
