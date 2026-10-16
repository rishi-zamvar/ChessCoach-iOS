import Foundation
import GRDB

/// Persists AI spend (`ai_call`) and cached explanations (`ai_explanation`).
public final class AIStore: AISpendLedger, @unchecked Sendable {
  let database: AppDatabase
  let calendar = Calendar(identifier: .gregorian)

  public init(database: AppDatabase) {
    self.database = database
  }

  struct CallRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_call"
    var at: Date
    var model: String
    var purpose: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var costUSD: Double
    var latencyMs: Double
  }

  struct ExplanationRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_explanation"
    var key: String
    var text: String
    var model: String
    var createdAt: Date
  }

  public func record(_ usage: AIUsage, purpose: String, latencyMs: Double) {
    let row = CallRow(
      at: Date(), model: usage.model, purpose: purpose, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
      cacheReadTokens: usage.cacheReadTokens, cacheWriteTokens: usage.cacheWriteTokens, costUSD: usage.costUSD, latencyMs: latencyMs)
    try? database.writer.write { try row.insert($0) }
  }

  public func spentThisMonth() -> Double { spent(since: startOfMonth(Date())) }

  public func spent(since date: Date) -> Double {
    (try? database.reader.read { db in
      try Double.fetchOne(db, sql: "SELECT COALESCE(SUM(costUSD), 0) FROM ai_call WHERE at >= ?", arguments: [date])
    }) ?? 0 ?? 0
  }

  public func callCount(since date: Date) -> Int {
    (try? database.reader.read { db in try CallRow.filter(Column("at") >= date).fetchCount(db) }) ?? 0
  }

  func startOfMonth(_ date: Date) -> Date {
    calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
  }

  public func cachedExplanation(key: String) -> String? {
    try? database.reader.read { db in try ExplanationRow.fetchOne(db, key: key)?.text }
  }

  public func cacheExplanation(key: String, text: String, model: String) {
    try? database.writer.write { db in try ExplanationRow(key: key, text: text, model: model, createdAt: Date()).save(db) }
  }

  static func migrate(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("v4-ai") { db in
      try db.create(table: "ai_call") { t in
        t.autoIncrementedPrimaryKey("rowid")
        t.column("at", .datetime).notNull().indexed()
        t.column("model", .text).notNull()
        t.column("purpose", .text).notNull()
        t.column("inputTokens", .integer).notNull()
        t.column("outputTokens", .integer).notNull()
        t.column("cacheReadTokens", .integer).notNull()
        t.column("cacheWriteTokens", .integer).notNull()
        t.column("costUSD", .double).notNull()
        t.column("latencyMs", .double).notNull()
      }
      try db.create(table: "ai_explanation") { t in
        t.primaryKey("key", .text)
        t.column("text", .text).notNull()
        t.column("model", .text).notNull()
        t.column("createdAt", .datetime).notNull()
      }
    }
  }
}
