import Foundation
import GRDB

/// The app's single SQLite store.
public final class AppDatabase: Sendable {
  public let writer: any DatabaseWriter
  public var reader: any DatabaseReader { writer }

  public init(_ writer: any DatabaseWriter) throws {
    self.writer = writer
    try Self.migrator.migrate(writer)
  }

  /// On-disk database in Application Support.
  public static func onDisk(named name: String = "chesscoach.sqlite") throws -> AppDatabase {
    let folder = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let url = folder.appendingPathComponent(name)
    var config = Configuration()
    config.foreignKeysEnabled = true
    return try AppDatabase(DatabasePool(path: url.path, configuration: config))
  }

  public static func inMemory() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "game") { t in
        t.primaryKey("id", .text)
        t.column("source", .text).notNull()
        t.column("pgn", .text).notNull()
        t.column("white", .text).notNull()
        t.column("black", .text).notNull()
        t.column("userColor", .text).notNull()
        t.column("result", .text).notNull()
        t.column("termination", .text).notNull()
        t.column("timeControl", .text).notNull()
        t.column("opponentKind", .text).notNull()
        t.column("startedAt", .datetime).notNull()
        t.column("endedAt", .datetime).notNull().indexed()
      }
      try db.create(table: "step_event") { t in
        t.primaryKey("rowid", .integer)
        t.column("id", .text).notNull()
        t.column("runID", .text).notNull()
        t.column("parentID", .text)
        t.column("step", .text).notNull()
        t.column("phase", .text).notNull()
        t.column("done", .integer)
        t.column("total", .integer)
        t.column("durationMs", .double)
        t.column("metadata", .text).notNull()
        t.column("error", .text)
        t.column("timestamp", .datetime).notNull().indexed()
      }
      try db.create(index: "step_event_step_phase", on: "step_event", columns: ["step", "phase"])
    }
    migrator.registerMigration("v2-analysis") { db in
      try db.alter(table: "game") { t in
        t.add(column: "whiteElo", .integer)
        t.add(column: "blackElo", .integer)
        t.add(column: "timeClass", .text)
        t.add(column: "chessComAccuracy", .double)
      }
      try db.create(table: "position_cache") { t in
        t.primaryKey("fenKey", .text)
        t.column("depth", .integer).notNull()
        t.column("lines", .text).notNull()
      }
      try db.create(table: "game_analysis") { t in
        t.primaryKey("gameID", .text)
        t.column("depth", .integer).notNull()
        t.column("json", .text).notNull()
        t.column("createdAt", .datetime).notNull()
      }
      try db.create(table: "mistake") { t in
        t.autoIncrementedPrimaryKey("rowid")
        t.column("gameID", .text).notNull().indexed()
        t.column("ply", .integer).notNull()
        t.column("label", .text).notNull()
        t.column("mistakeType", .text).notNull()
        t.column("motifs", .text).notNull()
        t.column("phase", .text).notNull()
        t.column("fen", .text).notNull()
        t.column("bestUCI", .text)
        t.column("timeTrouble", .boolean).notNull()
        t.column("endedAt", .datetime).notNull().indexed()
      }
    }
    TrainingStore.migrate(&migrator)
    return migrator
  }
}
