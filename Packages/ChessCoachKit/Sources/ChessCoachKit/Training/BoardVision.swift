import ChessKit
import Foundation

/// Generated board-vision and safety drills.
public enum BoardVision {
  /// "Tap e4": a random square to find (deterministic with a seeded source).
  public static func coordinateTargets(count: Int, random: RandomSource) -> [Square] {
    (0..<count).map { _ in Square.allCases[min(63, Int(random.next() * 64))] }
  }

  /// Every checking or capturing move for the side to move (the CCT drill answer).
  public static func checksAndCaptures(fen: String) -> Set<String> {
    let session = GameSession(startFEN: fen)
    var result = Set<String>()
    for piece in session.position.pieces where piece.color == session.sideToMove {
      for target in session.legalTargets(from: piece.square) {
        var copy = session
        let promo: Piece.Kind? = copy.isPromotion(from: piece.square, to: target) ? .queen : nil
        guard case .applied(let played) = copy.apply(from: piece.square, to: target, promotion: promo) else { continue }
        let isCapture: Bool = if case .capture = played.move.result { true } else { false }
        if isCapture || played.move.checkState != .none { result.insert(played.uci) }
      }
    }
    return result
  }

  /// "Is this move safe?" questions from a Lichess puzzle: the opponent's setup move
  /// (`Moves[0]`) is the blunder; the puzzle's first solution move is a good move.
  public struct SafetyQuestion: Equatable, Sendable {
    public var fen: String
    public var move: String
    public var isSafe: Bool
    /// The punishing reply when unsafe.
    public var refutation: String?
    /// Moves to play out from `fen`, starting with `move` (the punishment, or what the safe move achieves).
    public var line: [String] = []
    /// Why it's a blunder or why it's safe, in plain words.
    public var why: String = ""
  }

  public static func safetyQuestions(from puzzle: Puzzle) -> [SafetyQuestion] {
    guard puzzle.moves.count >= 2 else { return [] }
    var session = GameSession(startFEN: puzzle.fen)
    let unsafeWhy = blunderWhy(fen: puzzle.fen, line: puzzle.moves)
    let unsafe = SafetyQuestion(
      fen: puzzle.fen, move: puzzle.moves[0], isSafe: false, refutation: puzzle.moves[1], line: puzzle.moves, why: unsafeWhy)
    session.apply(uci: puzzle.moves[0])
    let afterFEN = session.position.fen
    // The solver's move is sound by construction (Lichess only-move solutions).
    let safe = SafetyQuestion(
      fen: afterFEN, move: puzzle.moves[1], isSafe: true, refutation: nil, line: Array(puzzle.moves.dropFirst()),
      why: safeWhy(fen: afterFEN, move: puzzle.moves[1]))
    return [unsafe, safe]
  }

  /// The move, the reply that punishes it, and what the whole line costs.
  static func blunderWhy(fen: String, line: [String]) -> String {
    var game = GameSession(startFEN: fen)
    let mover = game.sideToMove
    let san = FactExtractor.sanLine(fen: fen, ucis: line)
    var parts = [Explainer.reason(fen: fen, uci: line[0]) ?? "\(san.first ?? "")."]
    game.apply(uci: line[0])
    if line.count > 1, let reply = Explainer.reason(fen: game.position.fen, uci: line[1]) { parts.append("But \(reply)") }
    var mated = false
    for uci in line.dropFirst() {
      if case .applied(let m) = game.apply(uci: uci), m.move.checkState == .checkmate { mated = true }
    }
    let lost = material(fen, mover) - material(game.position.fen, mover) - (material(fen, mover.opposite) - material(game.position.fen, mover.opposite))
    if mated {
      if !(parts.last ?? "").contains("checkmate") { parts.append("The line ends in checkmate.") }
    } else if lost >= 1 {
      let what = lost >= 8 ? "a queen" : lost >= 5 ? "a rook" : lost >= 3 ? "a piece" : lost == 1 ? "a pawn" : "two pawns"
      parts.append(line.count > 2 ? "Play it out: you end up \(what) down." : "You end up \(what) down.")
    }
    return parts.joined(separator: " ")
  }

  static func material(_ fen: String, _ color: Piece.Color) -> Int {
    (Position(fen: fen)?.pieces ?? []).filter { $0.color == color && $0.kind != .king }.reduce(0) { $0 + PieceValue.of($1.kind) }
  }

  /// What the move does, and that it leaves nothing loose.
  static func safeWhy(fen: String, move: String) -> String {
    var parts: [String] = []
    if let reason = Explainer.reason(fen: fen, uci: move) { parts.append(reason) }
    var s = GameSession(startFEN: fen)
    let mover = s.sideToMove
    s.apply(uci: move)
    if FactExtractor.hangingPieces(fen: s.position.fen, of: mover).isEmpty {
      parts.append("After it, nothing of yours can be taken for free.")
    } else {
      parts.append("Something is left loose, but taking it costs them more.")
    }
    return parts.joined(separator: " ")
  }
}
