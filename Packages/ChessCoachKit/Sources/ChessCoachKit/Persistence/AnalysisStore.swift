import Foundation
import GRDB

/// Engine lines per position (FEN without counters), reused across games and re-runs.
public final class PositionCache: @unchecked Sendable {
  let database: AppDatabase

  public init(database: AppDatabase) {
    self.database = database
  }

  struct Row: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "position_cache"
    var fenKey: String
    var depth: Int
    var lines: String
  }

  struct StoredLine: Codable {
    var multipv: Int
    var depth: Int
    var cp: Int?
    var mate: Int?
    var pv: [String]
  }

  public func lookup(fenKey: String, minDepth: Int) -> [EngineLine]? {
    guard let row = try? database.reader.read({ try Row.fetchOne($0, key: fenKey) }), row.depth >= minDepth,
      let stored = try? JSONDecoder().decode([StoredLine].self, from: Data(row.lines.utf8)), !stored.isEmpty
    else { return nil }
    return stored.map { s in
      EngineLine(multipv: s.multipv, depth: s.depth, score: s.mate.map(EngineScore.mate) ?? .centipawns(s.cp ?? 0), pv: s.pv)
    }
  }

  /// Saves lines unless a deeper analysis of this position is already cached.
  public func store(fenKey: String, depth: Int, lines: [EngineLine]) {
    if let existing = try? database.reader.read({ try Row.fetchOne($0, key: fenKey) }), existing.depth > depth { return }
    let stored = lines.map { line -> StoredLine in
      switch line.score {
      case .centipawns(let cp): StoredLine(multipv: line.multipv, depth: line.depth, cp: cp, mate: nil, pv: line.pv)
      case .mate(let m): StoredLine(multipv: line.multipv, depth: line.depth, cp: nil, mate: m, pv: line.pv)
      }
    }
    guard let json = try? String(data: JSONEncoder().encode(stored), encoding: .utf8) else { return }
    try? database.writer.write { db in
      try Row(fenKey: fenKey, depth: depth, lines: json).save(db)
    }
  }
}

/// One row per mistake (feeds Recurring Mistakes and the training weakness profile).
public struct MistakeRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "mistake"
  public var gameID: String
  public var ply: Int
  public var label: String
  public var mistakeType: String
  public var motifs: String
  public var phase: String
  public var fen: String
  public var bestUCI: String?
  public var timeTrouble: Bool
  public var endedAt: Date
}

/// A recurring pattern across games.
public struct MistakePattern: Equatable, Sendable, Identifiable {
  public var id: String { key }
  public var key: String
  public var title: String
  public var count: Int
  public var games: Int
}

/// Saves analyses and aggregates the user's mistakes across games.
public struct AnalysisStore: Sendable {
  let database: AppDatabase

  public init(database: AppDatabase) {
    self.database = database
  }

  struct Row: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "game_analysis"
    var gameID: String
    var depth: Int
    var json: String
    var createdAt: Date
  }

  public func save(_ analysis: GameAnalysis, endedAt: Date) throws {
    let json = String(data: try JSONEncoder().encode(analysis), encoding: .utf8) ?? "{}"
    let mistakes = analysis.moves.filter { $0.color == analysis.userColor && $0.label.isError }.map { m in
      MistakeRecord(
        gameID: analysis.gameID, ply: m.ply, label: m.label.rawValue, mistakeType: (m.mistakeType ?? .positional).rawValue,
        motifs: (m.facts?.punish?.motifs ?? m.facts?.best?.motifs ?? []).map(\.rawValue).joined(separator: ","),
        phase: (m.facts?.phase ?? .middlegame).rawValue, fen: m.fenBefore, bestUCI: m.bestUCI,
        timeTrouble: m.timeTrouble, endedAt: endedAt)
    }
    try database.writer.write { db in
      try Row(gameID: analysis.gameID, depth: analysis.depth, json: json, createdAt: analysis.createdAt).save(db)
      try MistakeRecord.filter(Column("gameID") == analysis.gameID).deleteAll(db)
      for m in mistakes { try m.insert(db) }
    }
  }

  public func analysis(gameID: String) throws -> GameAnalysis? {
    try database.reader.read { db in
      guard let row = try Row.fetchOne(db, key: gameID) else { return nil }
      return try JSONDecoder().decode(GameAnalysis.self, from: Data(row.json.utf8))
    }
  }

  public func analyzedGameIDs() throws -> Set<String> {
    try database.reader.read { db in Set(try String.fetchAll(db, sql: "SELECT gameID FROM game_analysis")) }
  }

  public func mistakes(limit: Int = 500) throws -> [MistakeRecord] {
    try database.reader.read { db in
      try MistakeRecord.order(Column("endedAt").desc).limit(limit).fetchAll(db)
    }
  }

  /// Most frequent mistake types and motifs across the user's analyzed games.
  public func recurringPatterns(limit: Int = 6) throws -> [MistakePattern] {
    let all = try mistakes()
    var byKey: [String: (title: String, count: Int, games: Set<String>)] = [:]
    for m in all {
      let type = MistakeType(rawValue: m.mistakeType) ?? .positional
      var keys = [("type:\(type.rawValue)", type.displayName)]
      for motif in m.motifs.split(separator: ",").compactMap({ Motif(rawValue: String($0)) })
      where [.fork, .pin, .skewer, .discoveredAttack, .mate, .mateThreat, .backRankMate].contains(motif) {
        keys.append(("motif:\(motif.rawValue)", "\(motif.displayName)s"))
      }
      if m.timeTrouble { keys.append(("time", "Time trouble")) }
      for (key, title) in keys {
        var entry = byKey[key] ?? (title, 0, [])
        entry.count += 1
        entry.games.insert(m.gameID)
        byKey[key] = entry
      }
    }
    let patterns: [MistakePattern] = byKey.map { key, value in
      MistakePattern(key: key, title: value.title, count: value.count, games: value.games.count)
    }
    let sorted = patterns.sorted { a, b in a.count == b.count ? a.key < b.key : a.count > b.count }
    return Array(sorted.prefix(limit))
  }
}
