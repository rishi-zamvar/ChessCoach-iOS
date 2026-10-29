import ChessKit
import Foundation

/// Why a wrong puzzle move fails (spec W2): the opponent's punishing reply, played on the board,
/// plus one plain sentence built from engine-checked facts. Works offline, no AI needed.
public struct PuzzleRefutation: Equatable, Sendable {
  /// The opponent's reply to your move (UCI) and its SAN.
  public var reply: String
  public var replySAN: String
  /// Plies to animate after your move (just the reply: enough to show the punishment).
  public var plies: [String] { [reply] }
  public var caption: String

  /// `fen` is the puzzle position before your move; `punishLine` the engine's best line after it.
  public static func make(fen: String, wrong uci: String, punishLine: [String]) -> PuzzleRefutation? {
    guard let reply = punishLine.first, let played = FactExtractor.moveFacts(fen: fen, uci: uci) else { return nil }
    var session = GameSession(startFEN: fen)
    let mover = session.sideToMove
    guard case .applied = session.apply(uci: uci) else { return nil }
    let afterFEN = session.position.fen
    guard let punish = FactExtractor.moveFacts(fen: afterFEN, uci: reply) else { return nil }
    let you = played.san
    let them = punish.san
    let replyTo = String(reply.dropFirst(2).prefix(2))
    let caption: String
    if punish.motifs.contains(.mate) {
      caption = "\(you) allows \(them)."
    } else if let lost = FactExtractor.hangingPieces(fen: afterFEN, of: mover).first(where: { $0.square.notation == replyTo }) {
      caption = "\(you) leaves the \(FactExtractor.name(of: lost.kind)) on \(replyTo): \(them) wins it."
    } else if punish.motifs.contains(.fork), punish.targets.count >= 2 {
      caption = "\(you) allows \(them), forking the \(Explainer.list(punish.targets))."
    } else if punish.motifs.contains(.winsMaterial) || punish.materialWon >= 2 {
      caption = "\(you) lets \(them) win material."
    } else if punish.motifs.contains(.mateThreat) {
      caption = "\(you) allows \(them), threatening mate."
    } else if let motif = [Motif.pin, .skewer, .discoveredAttack].first(where: punish.motifs.contains) {
      caption = "\(you) allows \(them), a \(motif.displayName.lowercased())."
    } else {
      caption = "After \(you) \(them), the chance is gone. There's something stronger here."
    }
    return PuzzleRefutation(reply: reply, replySAN: them, caption: caption)
  }
}

/// A move that isn't the puzzle's but still wins counts as solved (spec W5).
public enum AlternativeWin {
  /// Scores are from the opponent's side to move (as the engine reports them after your move):
  /// accept a mate, or ≥ +3.0 for you that is within a pawn of the solution (and doesn't miss a forced mate).
  public static func accepts(afterYourMove yours: EngineScore, afterSolution solution: EngineScore) -> Bool {
    if case .mate(let n) = yours, n < 0 { return true }
    if case .mate(let n) = solution, n < 0 { return false }
    guard case .centipawns(let y) = yours, case .centipawns(let s) = solution else { return false }
    let you = -y
    let best = -s
    return you >= 300 && you >= best - 100
  }
}
