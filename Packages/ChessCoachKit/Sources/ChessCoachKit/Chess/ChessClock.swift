import ChessKit
import Foundation

public struct TimeControl: Sendable, Equatable, Hashable, Codable {
  /// Starting time per side in seconds; 0 means untimed.
  public var base: TimeInterval
  public var increment: TimeInterval

  public init(base: TimeInterval, increment: TimeInterval) {
    self.base = base
    self.increment = increment
  }

  public static let untimed = TimeControl(base: 0, increment: 0)
  public static let presets: [TimeControl] = [
    .untimed, .init(base: 600, increment: 0), .init(base: 900, increment: 10), .init(base: 1800, increment: 0),
  ]

  public var isTimed: Bool { base > 0 }

  public var label: String {
    guard isTimed else { return "No clock" }
    let minutes = Int(base / 60)
    return increment > 0 ? "\(minutes) | \(Int(increment))" : "\(minutes) min"
  }

  /// PGN TimeControl tag value.
  public var pgnTag: String { isTimed ? "\(Int(base))+\(Int(increment))" : "-" }
}

/// Two-sided game clock. Time is passed in explicitly so it is deterministic in tests.
public struct ChessClock: Sendable, Equatable {
  public let control: TimeControl
  public private(set) var running: Piece.Color?
  private var banked: [Piece.Color: TimeInterval]
  private var runningSince: Date?

  public init(control: TimeControl) {
    self.control = control
    banked = [.white: control.base, .black: control.base]
  }

  public mutating func start(_ color: Piece.Color, at now: Date) {
    running = color
    runningSince = now
  }

  /// `color` finished its move: bank its time, add increment, start the other side.
  public mutating func press(_ color: Piece.Color, at now: Date) {
    banked[color] = remaining(color, at: now) + control.increment
    start(color.opposite, at: now)
  }

  public mutating func pause(at now: Date) {
    if let running {
      banked[running] = remaining(running, at: now)
    }
    running = nil
    runningSince = nil
  }

  public func remaining(_ color: Piece.Color, at now: Date) -> TimeInterval {
    let bank = banked[color] ?? 0
    guard color == running, let since = runningSince else { return bank }
    return max(0, bank - now.timeIntervalSince(since))
  }

  public func flagged(at now: Date) -> Piece.Color? {
    guard control.isTimed, let running, remaining(running, at: now) <= 0 else { return nil }
    return running
  }

  /// Under 10% of the base time or under 20 seconds.
  public func isLow(_ color: Piece.Color, at now: Date) -> Bool {
    guard control.isTimed else { return false }
    let left = remaining(color, at: now)
    return left < control.base * 0.1 || left < 20
  }
}
