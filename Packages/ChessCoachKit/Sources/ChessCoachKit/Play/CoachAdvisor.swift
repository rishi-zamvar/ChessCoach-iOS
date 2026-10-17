import Foundation

/// The engine's view of a position, for the side to move.
public struct CoachAssessment: Sendable, Equatable {
  public var bestUCI: String
  /// Win% (0…100) for the side to move.
  public var winPercent: Double
  /// Forced mate in N for the side to move (negative: they get mated).
  public var mate: Int?
  /// Principal variation (UCI), best move first.
  public var line: [String]

  public init(bestUCI: String, winPercent: Double, mate: Int? = nil, line: [String] = []) {
    self.bestUCI = bestUCI
    self.winPercent = winPercent
    self.mate = mate
    self.line = line.isEmpty ? [bestUCI] : line
  }
}

/// Judges positions for Play Coach.
public protocol CoachAdvisor: Sendable {
  func assess(fen: String) async throws -> CoachAssessment
}

/// Stockfish at a modest depth: fast enough to run after every move.
public struct StockfishCoach: CoachAdvisor {
  let host: EngineHost
  let depth: Int

  public init(host: EngineHost, depth: Int = 10) {
    self.host = host
    self.depth = depth
  }

  public func assess(fen: String) async throws -> CoachAssessment {
    let result = try await host.search(.stockfish, fen: fen, limit: .depth(depth))
    let top = result.lines.first
    var mate: Int?
    if case .mate(let n)? = top?.score { mate = n }
    return CoachAssessment(
      bestUCI: result.bestMove, winPercent: top.map { WinChance.winPercent($0.score) } ?? 50, mate: mate, line: top?.pv ?? [])
  }
}

/// The coach stopped the game ("Hold up") before the bot replies.
public struct CoachPause: Equatable, Sendable {
  public var label: MoveClass
  public var playedSAN: String
  public var bestUCI: String
  public var bestSAN: String
  public var explanation: String
  public var kind: HoldUpKind = .mistake

  /// Card heading.
  public var title: String {
    switch kind {
    case .hungPiece: "Hold up: your piece is loose"
    case .missedMate: "Hold up: checkmate was there"
    case .missedFree: "Hold up: a free piece"
    case .missedTactic: "Hold up: a stronger idea"
    case .allowsTactic: "Hold up: watch their reply"
    case .ignoredThreat: "Hold up: their threat"
    case .aimless: "Hold up: what's the plan?"
    case .passiveKing: "Hold up: use your king"
    case .leftBook: "Hold up: not your line"
    case .mistake, .blunder: "\(playedSAN) is a \(label.displayName.lowercased())"
    }
  }
}
