import ChessCoachKit
import Foundation

/// Quick on-device Stockfish checks for puzzles: what punishes a move, whether a different move
/// still wins, and how much a move lost. Short searches (≤ ~0.4 s) so the board stays responsive.
@MainActor
struct PuzzleEngine {
  let host: EngineHost

  init?(_ env: AppEnvironment) {
    guard let host = env.engineHost else { return nil }
    self.host = host
  }

  static let limit = SearchLimit.depthOrTime(depth: 14, milliseconds: 400)

  /// Best line and score (side to move) in `fen`.
  func best(_ fen: String) async -> EngineLine? {
    try? await host.search(.stockfish, fen: fen, limit: Self.limit).lines.first
  }

  /// The position after `uci` from `fen`, or nil if illegal.
  static func after(_ fen: String, _ uci: String) -> String? {
    var s = GameSession(startFEN: fen)
    guard case .applied = s.apply(uci: uci) else { return nil }
    return s.position.fen
  }

  /// Your wrong move, explained by the engine's reply.
  func refutation(fen: String, wrong uci: String) async -> PuzzleRefutation? {
    guard let after = Self.after(fen, uci), let line = await best(after) else { return nil }
    return PuzzleRefutation.make(fen: fen, wrong: uci, punishLine: line.pv)
  }

  /// Does `uci` (not the puzzle's move) still win about as well as `solution`? (spec W5)
  func alsoWins(fen: String, uci: String, solution: String) async -> Bool {
    guard let mine = Self.after(fen, uci), let theirs = Self.after(fen, solution),
      let yours = await best(mine)?.score, let best = await best(theirs)?.score
    else { return false }
    return AlternativeWin.accepts(afterYourMove: yours, afterSolution: best)
  }

  /// Expected points `uci` loses for the side to move in `fen` (0 = as good as the best move).
  func loss(fen: String, uci: String) async -> Double {
    guard let after = Self.after(fen, uci), let before = await best(fen)?.score, let reply = await best(after)?.score else { return 0 }
    let winBefore = WinChance.winPercent(before) / 100
    let winAfter = 1 - WinChance.winPercent(reply) / 100
    return max(0, winBefore - winAfter)
  }
}
