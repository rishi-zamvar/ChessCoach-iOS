import Foundation
import GRDB

/// Persists step events to `step_event` off the caller's thread.
public final class DatabaseSink: TelemetrySink, @unchecked Sendable {
  private let database: AppDatabase
  private let queue = DispatchQueue(label: "chesscoach.telemetry.db", qos: .utility)

  public init(database: AppDatabase) {
    self.database = database
  }

  public func record(_ event: StepEvent) {
    let record = StepEventRecord(event)
    queue.async { [database] in
      // Logging must never crash or block the app; a failed write is dropped.
      try? database.writer.write { try record.insert($0) }
    }
  }

  /// Waits until queued writes are done (tests, app backgrounding).
  public func flush() {
    queue.sync {}
  }

  /// Deletes events older than `date` (the app keeps 30 days).
  public func prune(olderThan date: Date) throws {
    flush()
    _ = try database.writer.write { db in
      try StepEventRecord.filter(Column("timestamp") < date).deleteAll(db)
    }
  }

  /// Median duration of finished runs of `step`, used for progress ETAs.
  public func medianDuration(step: String) throws -> Double? {
    flush()
    let durations = try database.reader.read { db in
      try Double.fetchAll(
        db,
        sql: "SELECT durationMs FROM step_event WHERE step = ? AND phase = 'finish' AND durationMs IS NOT NULL ORDER BY durationMs",
        arguments: [step])
    }
    guard !durations.isEmpty else { return nil }
    let mid = durations.count / 2
    return durations.count.isMultiple(of: 2) ? (durations[mid - 1] + durations[mid]) / 2 : durations[mid]
  }

  /// Recent events, newest first (debug screen).
  public func recent(limit: Int = 200) throws -> [StepEvent] {
    flush()
    return try database.reader.read { db in
      try StepEventRecord.order(Column("rowid").desc).limit(limit).fetchAll(db).map(\.event)
    }
  }
}
