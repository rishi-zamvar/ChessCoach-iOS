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
  }

  public static func safetyQuestions(from puzzle: Puzzle) -> [SafetyQuestion] {
    guard puzzle.moves.count >= 2 else { return [] }
    var session = GameSession(startFEN: puzzle.fen)
    let unsafe = SafetyQuestion(fen: puzzle.fen, move: puzzle.moves[0], isSafe: false, refutation: puzzle.moves[1])
    session.apply(uci: puzzle.moves[0])
    let afterFEN = session.position.fen
    // The solver's move is sound by construction (Lichess only-move solutions).
    let safe = SafetyQuestion(fen: afterFEN, move: puzzle.moves[1], isSafe: true, refutation: nil)
    return [unsafe, safe]
  }
}
