import GRDB
import XCTest
@testable import ChessCoachKit

final class PersistenceTests: XCTestCase {
  func makeGame(id: String, endedAt: Date) -> GameRecord {
    GameRecord(
      id: id, source: .local, pgn: "1. e4 e5 *", white: "You", black: "Maia 1100",
      userColor: "white", result: "1-0", termination: "checkmate", timeControl: "10+0",
      opponentKind: "maia-1100", startedAt: endedAt.addingTimeInterval(-600), endedAt: endedAt)
  }

  func test_givenFreshDatabase_whenMigrated_thenTablesExist() throws {
    let db = try AppDatabase.inMemory()
    try db.reader.read { db in
      XCTAssertTrue(try db.tableExists("game"))
      XCTAssertTrue(try db.tableExists("step_event"))
    }
  }

  func test_givenSavedGame_whenFetchedById_thenRoundTrips() throws {
    let store = GameStore(database: try AppDatabase.inMemory())
    let game = makeGame(id: "g1", endedAt: Date(timeIntervalSince1970: 1_000_000))
    try store.save(game)
    XCTAssertEqual(try store.game(id: "g1"), game)
  }

  func test_givenSeveralGames_whenRecent_thenNewestFirstAndLimited() throws {
    let store = GameStore(database: try AppDatabase.inMemory())
    for i in 0..<5 {
      try store.save(makeGame(id: "g\(i)", endedAt: Date(timeIntervalSince1970: Double(1_000_000 + i))))
    }
    XCTAssertEqual(try store.recent(limit: 3).map(\.id), ["g4", "g3", "g2"])
  }

  func test_givenDatabaseSink_whenEventsRecorded_thenPersistedAndMedianComputed() throws {
    let database = try AppDatabase.inMemory()
    let sink = DatabaseSink(database: database)
    let run = UUID()
    for ms in [10.0, 30.0, 20.0] {
      sink.record(StepEvent(id: UUID(), runID: run, parentID: nil, step: "x", phase: .finish, durationMs: ms))
    }
    sink.record(StepEvent(id: UUID(), runID: run, parentID: nil, step: "x", phase: .start))
    sink.flush()
    XCTAssertEqual(try database.reader.read { try StepEventRecord.fetchCount($0) }, 4)
    XCTAssertEqual(try sink.medianDuration(step: "x"), 20)
    XCTAssertNil(try sink.medianDuration(step: "missing"))
  }

  func test_givenOldEvents_whenPruned_thenOnlyRecentRemain() throws {
    let database = try AppDatabase.inMemory()
    let sink = DatabaseSink(database: database)
    let now = Date()
    sink.record(StepEvent(id: UUID(), runID: UUID(), parentID: nil, step: "old", phase: .finish, timestamp: now.addingTimeInterval(-40 * 86400)))
    sink.record(StepEvent(id: UUID(), runID: UUID(), parentID: nil, step: "new", phase: .finish, timestamp: now))
    sink.flush()
    try sink.prune(olderThan: now.addingTimeInterval(-30 * 86400))
    let steps = try database.reader.read { try String.fetchAll($0, sql: "SELECT step FROM step_event") }
    XCTAssertEqual(steps, ["new"])
  }

  func test_givenEventWithMetadata_whenPersisted_thenMetadataDecodes() throws {
    let database = try AppDatabase.inMemory()
    let sink = DatabaseSink(database: database)
    let event = StepEvent(id: UUID(), runID: UUID(), parentID: UUID(), step: "m", phase: .fail, metadata: ["k": .int(3)], error: "e")
    sink.record(event)
    sink.flush()
    let loaded = try database.reader.read { try StepEventRecord.fetchOne($0) }!.event
    XCTAssertEqual(loaded.metadata, ["k": .int(3)])
    XCTAssertEqual(loaded.parentID, event.parentID)
    XCTAssertEqual(loaded.error, "e")
  }
}
