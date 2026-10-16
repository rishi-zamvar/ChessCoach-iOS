import Foundation

/// Judges positions for Play Coach.
public protocol CoachAdvisor: Sendable {
  /// Best move and the side-to-move's win% (0…100) for `fen`.
  func assess(fen: String) async throws -> (bestUCI: String, winPercent: Double)
}

/// Stockfish at a modest depth: fast enough to run after every move.
public struct StockfishCoach: CoachAdvisor {
  let host: EngineHost
  let depth: Int

  public init(host: EngineHost, depth: Int = 10) {
    self.host = host
    self.depth = depth
  }

  public func assess(fen: String) async throws -> (bestUCI: String, winPercent: Double) {
    let result = try await host.search(.stockfish, fen: fen, limit: .depth(depth))
    let win = result.lines.first.map { WinChance.winPercent($0.score) } ?? 50
    return (result.bestMove, win)
  }
}

/// The coach stopped the game after a user mistake.
public struct CoachPause: Equatable, Sendable {
  public var label: MoveClass
  public var playedSAN: String
  public var bestUCI: String
  public var bestSAN: String
  public var explanation: String
}
