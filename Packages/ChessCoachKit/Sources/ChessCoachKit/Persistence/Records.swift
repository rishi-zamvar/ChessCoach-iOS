import Foundation
import GRDB

/// A finished game (played in the app, or imported in M2).
public struct GameRecord: Codable, Sendable, Equatable, Identifiable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "game"

  public enum Source: String, Codable, Sendable { case local, chesscom }

  public var id: String
  public var source: Source
  public var pgn: String
  public var white: String
  public var black: String
  public var userColor: String
  public var result: String
  public var termination: String
  public var timeControl: String
  public var opponentKind: String
  public var startedAt: Date
  public var endedAt: Date
  public var whiteElo: Int?
  public var blackElo: Int?
  public var timeClass: String?
  public var chessComAccuracy: Double?

  public init(
    id: String, source: Source, pgn: String, white: String, black: String, userColor: String,
    result: String, termination: String, timeControl: String, opponentKind: String,
    startedAt: Date, endedAt: Date, whiteElo: Int? = nil, blackElo: Int? = nil, timeClass: String? = nil,
    chessComAccuracy: Double? = nil
  ) {
    self.whiteElo = whiteElo
    self.blackElo = blackElo
    self.timeClass = timeClass
    self.chessComAccuracy = chessComAccuracy
    self.id = id
    self.source = source
    self.pgn = pgn
    self.white = white
    self.black = black
    self.userColor = userColor
    self.result = result
    self.termination = termination
    self.timeControl = timeControl
    self.opponentKind = opponentKind
    self.startedAt = startedAt
    self.endedAt = endedAt
  }
}

/// Row form of a StepEvent.
struct StepEventRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "step_event"

  var id: String
  var runID: String
  var parentID: String?
  var step: String
  var phase: String
  var done: Int?
  var total: Int?
  var durationMs: Double?
  var metadata: String
  var error: String?
  var timestamp: Date

  init(_ e: StepEvent) {
    id = e.id.uuidString
    runID = e.runID.uuidString
    parentID = e.parentID?.uuidString
    step = e.step
    phase = e.phase.rawValue
    done = e.done
    total = e.total
    durationMs = e.durationMs
    metadata = (try? String(data: JSONEncoder().encode(e.metadata), encoding: .utf8)) ?? "{}"
    error = e.error
    timestamp = e.timestamp
  }

  var event: StepEvent {
    StepEvent(
      id: UUID(uuidString: id) ?? UUID(),
      runID: UUID(uuidString: runID) ?? UUID(),
      parentID: parentID.flatMap(UUID.init(uuidString:)),
      step: step,
      phase: StepPhase(rawValue: phase) ?? .finish,
      done: done, total: total, durationMs: durationMs,
      metadata: (try? JSONDecoder().decode([String: JSONValue].self, from: Data(metadata.utf8))) ?? [:],
      error: error, timestamp: timestamp)
  }
}

extension GameRecord {
  /// A chess.com game as a stored record.
  public init(imported g: ImportedGame) {
    self.init(
      id: g.id, source: .chesscom, pgn: g.pgn, white: g.white, black: g.black, userColor: g.userColor,
      result: g.result, termination: g.termination, timeControl: g.timeControl, opponentKind: "chesscom",
      startedAt: g.endedAt, endedAt: g.endedAt, whiteElo: g.whiteElo, blackElo: g.blackElo,
      timeClass: g.timeClass, chessComAccuracy: g.chessComAccuracy)
  }
}
