import Foundation

/// Lifecycle phase of a logged step.
public enum StepPhase: String, Codable, Sendable {
  case start, progress, finish, fail
}

/// A small JSON value for event metadata.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let i = try? c.decode(Int.self) {
      self = .int(i)
    } else if let d = try? c.decode(Double.self) {
      self = .double(d)
    } else {
      self = .string(try c.decode(String.self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let s): try c.encode(s)
    case .int(let i): try c.encode(i)
    case .double(let d): try c.encode(d)
    case .bool(let b): try c.encode(b)
    case .null: try c.encodeNil()
    }
  }

  public var description: String {
    switch self {
    case .string(let s): s
    case .int(let i): String(i)
    case .double(let d): String(format: "%.3f", d)
    case .bool(let b): String(b)
    case .null: "null"
    }
  }
}

/// One structured log record. Every pipeline step emits start → (progress…) → finish|fail
/// with a shared `id`; nested steps point at their parent via `parentID` and share `runID`.
public struct StepEvent: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var runID: UUID
  public var parentID: UUID?
  public var step: String
  public var phase: StepPhase
  public var done: Int?
  public var total: Int?
  public var durationMs: Double?
  public var metadata: [String: JSONValue]
  public var error: String?
  public var timestamp: Date

  public init(
    id: UUID, runID: UUID, parentID: UUID?, step: String, phase: StepPhase,
    done: Int? = nil, total: Int? = nil, durationMs: Double? = nil,
    metadata: [String: JSONValue] = [:], error: String? = nil, timestamp: Date = Date()
  ) {
    self.id = id
    self.runID = runID
    self.parentID = parentID
    self.step = step
    self.phase = phase
    self.done = done
    self.total = total
    self.durationMs = durationMs
    self.metadata = metadata
    self.error = error
    self.timestamp = timestamp
  }
}
