import ChessKit
import Foundation

/// Why a move was a mistake, in three parts: what your move did (and allowed), why the
/// better move is better, and the habit that would have caught it. Engine-free text built
/// from the analysis, so every move it names is real.
public struct MoveInsight: Equatable, Sendable {
  public var played: String
  public var better: String
  public var habit: String
  /// The punishing line after your move and the better line, as UCI from the position before your move.
  public var playedLine: [String]
  public var betterLine: [String]

  public static func make(_ move: MoveAnalysis) -> MoveInsight? {
    guard move.label.isError, let best = move.bestUCI, best != move.uci else { return nil }
    let fen = move.fenBefore
    var after = GameSession(startFEN: fen)
    after.apply(uci: move.uci)
    let punishUCI = ucis(fen: after.position.fen, san: move.facts?.punishLineSAN ?? [])

    var played = Explainer.reason(fen: fen, uci: move.uci) ?? "\(move.san)."
    if let reply = punishUCI.first, let replyText = Explainer.reason(fen: after.position.fen, uci: reply) {
      played += " Their best reply: \(replyText)"
    } else if let loose = move.facts?.hangingAfter.first {
      played += " It leaves your \(loose.kind) on \(loose.square) loose."
    }
    if let result = outcome(fen: fen, line: [move.uci] + punishUCI, ahead: false) { played += " " + result }

    let betterUCI = ucis(fen: fen, san: move.bestLine)
    let line = betterUCI.isEmpty ? [best] : betterUCI
    var better = Explainer.reason(fen: fen, uci: best) ?? "\(move.facts?.best?.san ?? best) was better."
    let sanLine = FactExtractor.sanLine(fen: fen, ucis: Array(line.prefix(4)))
    if sanLine.count >= 3 { better += " The line: \(sanLine.joined(separator: " "))." }
    if let result = outcome(fen: fen, line: line, ahead: true) { better += " " + result }

    return MoveInsight(
      played: played, better: better, habit: habit(move.mistakeType ?? .positional),
      playedLine: [move.uci] + punishUCI, betterLine: line)
  }

  /// The thinking habit behind each kind of mistake: why it was easy to miss.
  public static func habit(_ type: MistakeType) -> String {
    switch type {
    case .missedTactic:
      "You missed it because you didn't scan your own forcing moves. Before settling on a move, list every check, capture and threat you have."
    case .allowedTactic:
      "You missed it because you didn't check what your move allowed. After choosing a move, ask: what are their checks, captures and threats now?"
    case .hungMaterial:
      "You missed it because a piece was left without enough defenders. Before letting go, count who attacks and who defends the square."
    case .endgameError:
      "Endgames punish rushing. Bring your king in and count moves before pushing pawns."
    case .failedConversion:
      "When you're ahead, keep it simple: trade pieces, stop their counterplay, then cash in."
    case .positional:
      "No tactic here: the better move improves your worst piece or stops their plan. Ask what your least active piece wants."
    }
  }

  /// SAN moves from `fen` → UCI, stopping at the first one that doesn't parse.
  public static func ucis(fen: String, san: [String]) -> [String] {
    var game = GameSession(startFEN: fen)
    var out: [String] = []
    for s in san {
      guard let move = Move(san: s, position: game.position),
        case .applied(let played) = game.apply(from: move.start, to: move.end, promotion: move.promotedPiece?.kind)
      else { break }
      out.append(played.uci)
    }
    return out
  }

  /// What a line nets the side to move at `fen`: mate, or material won (`ahead`) / lost (not `ahead`).
  static func outcome(fen: String, line: [String], ahead: Bool) -> String? {
    var game = GameSession(startFEN: fen)
    let mover = game.sideToMove
    var mateBy: Piece.Color?
    for uci in line {
      if case .applied(let m) = game.apply(uci: uci), m.move.checkState == .checkmate { mateBy = m.color }
    }
    if let mateBy { return mateBy == mover ? (ahead ? "It ends in checkmate for you." : nil) : "It ends in checkmate against you." }
    let swing = (BoardVision.material(game.position.fen, mover) - BoardVision.material(fen, mover))
      - (BoardVision.material(game.position.fen, mover.opposite) - BoardVision.material(fen, mover.opposite))
    let size = abs(swing)
    let what = size >= 8 ? "a queen" : size >= 5 ? "a rook" : size >= 3 ? "a piece" : size == 2 ? "two pawns" : "a pawn"
    if ahead, swing >= 1 { return "You come out \(what) up." }
    if !ahead, swing <= -1 { return "You end up \(what) down." }
    return nil
  }
}
