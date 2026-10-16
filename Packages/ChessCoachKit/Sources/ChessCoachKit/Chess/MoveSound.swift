import ChessKit

/// Every sound the app plays. Raw values are the bundled file names (`<raw>.wav`).
public enum SoundEvent: String, CaseIterable, Sendable {
  case move, capture, castle, check, promote, illegal, premove, gameStart, gameEnd, lowTime

  /// The sound for a move just played. Priority: game end > check > promote > castle > capture > move.
  public static func forMove(_ played: PlayedMove, gameOver: Bool) -> SoundEvent {
    if gameOver { return .gameEnd }
    if played.move.checkState == .check { return .check }
    if played.move.promotedPiece != nil { return .promote }
    switch played.move.result {
    case .castle: return .castle
    case .capture: return .capture
    case .move: return .move
    }
  }
}

/// Where sounds and haptics go (the app plays them; tests record them).
@MainActor
public protocol SoundSink: AnyObject {
  func play(_ event: SoundEvent)
}

/// Test/preview sink that remembers what was played.
@MainActor
public final class RecordingSoundSink: SoundSink {
  public private(set) var played: [SoundEvent] = []
  public init() {}
  public func play(_ event: SoundEvent) { played.append(event) }
}
