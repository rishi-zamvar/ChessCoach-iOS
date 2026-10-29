import ChessKit
import Foundation

/// One puzzle attempt (Lichess semantics): the FEN is *before* the opponent's move;
/// `moves[0]` is that setup move, then the user and the opponent alternate.
/// Any checkmating final move is accepted.
public struct PuzzleSession: Sendable {
  public enum Result: Equatable, Sendable {
    /// Right move; the opponent replied with `reply` (UCI) if the puzzle continues.
    case correct(reply: String?)
    case solved
    case wrong
    case ignored
  }

  public enum Hint: Equatable, Sendable {
    case theme(String)
    case piece(Square)
    case move(from: Square, to: Square)
  }

  public let puzzle: Puzzle
  /// false for "retry this position" items where the user is already on move.
  public let hasSetupMove: Bool
  public private(set) var game: GameSession
  /// Index into `puzzle.moves` of the next expected move.
  public private(set) var index = 0
  public private(set) var hintsUsed = 0
  public private(set) var wrongMoves: [String] = []
  public private(set) var isSolved = false
  /// A different move that also wins (spec W5); the intended line is shown as "also good".
  public private(set) var solvedByAlternative: String?

  public init(puzzle: Puzzle, hasSetupMove: Bool = true) {
    self.puzzle = puzzle
    self.hasSetupMove = hasSetupMove
    game = GameSession(startFEN: puzzle.fen)
  }

  private var ready: Bool { !hasSetupMove || index > 0 }

  /// Plays the opponent's setup move (animate it in the UI). Returns it.
  @discardableResult
  public mutating func playSetup() -> String? {
    guard hasSetupMove, index == 0, let first = puzzle.moves.first else { return nil }
    game.apply(uci: first)
    index = 1
    return first
  }

  /// The side the user plays.
  public var userColor: Piece.Color {
    let side = Position(fen: puzzle.fen)?.sideToMove ?? .white
    return hasSetupMove ? side.opposite : side
  }

  public var expectedMove: String? { index < puzzle.moves.count ? puzzle.moves[index] : nil }
  public var failedFirstTry: Bool { !wrongMoves.isEmpty }

  public mutating func submit(from: Square, to: Square, promotion: Piece.Kind? = nil) -> Result {
    guard !isSolved, ready, let expected = expectedMove else { return .ignored }
    var trial = game
    // Promotion: use the piece the solution expects when the squares match (underpromotions).
    let expectedPromo = UCIMove(expected).flatMap { $0.from == from && $0.to == to ? $0.promotion : nil }
    let promo = promotion ?? expectedPromo ?? (trial.isPromotion(from: from, to: to) ? .queen : nil)
    guard case .applied(let played) = trial.apply(from: from, to: to, promotion: promo) else { return .ignored }
    let isLast = index == puzzle.moves.count - 1
    let matches = played.uci == expected
    let alternativeMate = isLast && played.move.checkState == .checkmate
    guard matches || alternativeMate else {
      wrongMoves.append(played.uci)
      return .wrong
    }
    game = trial
    index += 1
    if index >= puzzle.moves.count {
      isSolved = true
      return .solved
    }
    let reply = puzzle.moves[index]
    game.apply(uci: reply)
    index += 1
    if index >= puzzle.moves.count {
      isSolved = true
      return .solved
    }
    return .correct(reply: reply)
  }

  /// The engine says `uci` (just rejected by `submit`) still wins: count it as solved.
  @discardableResult
  public mutating func acceptAlternative(uci: String) -> Bool {
    guard !isSolved, ready else { return false }
    var trial = game
    guard case .applied(let played) = trial.apply(uci: uci) else { return false }
    if let i = wrongMoves.lastIndex(of: played.uci) { wrongMoves.remove(at: i) }
    game = trial
    isSolved = true
    solvedByAlternative = played.uci
    return true
  }

  public mutating func submit(uci: String) -> Result {
    guard let parsed = UCIMove(uci) else { return .ignored }
    return submit(from: parsed.from, to: parsed.to, promotion: parsed.promotion)
  }

  /// Next rung of the hint ladder: theme → piece → the move.
  public mutating func nextHint() -> Hint? {
    guard !isSolved, let expected = expectedMove.flatMap(UCIMove.init) else { return nil }
    hintsUsed += 1
    switch hintsUsed {
    case 1: return .theme(PuzzleThemes.displayName(puzzle.primaryTheme))
    case 2: return .piece(expected.from)
    default: return .move(from: expected.from, to: expected.to)
    }
  }

  /// Glicko score: clean solve 1; one hint 0.5; otherwise 0 (Lichess counts any failure as a loss).
  public var ratingScore: Double {
    if failedFirstTry || !isSolved { return 0 }
    return hintsUsed == 0 ? 1 : (hintsUsed == 1 ? 0.5 : 0)
  }

  public func grade(seconds: Double) -> AttemptGrade {
    AttemptGrade.from(solved: isSolved && !failedFirstTry, hintsUsed: hintsUsed, seconds: seconds)
  }
}

/// Friendly names for Lichess theme tags.
public enum PuzzleThemes {
  static let names: [String: String] = [
    "mateIn1": "Mate in 1", "mateIn2": "Mate in 2", "mateIn3": "Mate in 3", "mateIn4": "Mate in 4", "mateIn5": "Mate in 5",
    "mate": "Checkmate", "fork": "Fork", "pin": "Pin", "skewer": "Skewer", "hangingPiece": "Hanging piece",
    "discoveredAttack": "Discovered attack", "discoveredCheck": "Discovered check", "doubleCheck": "Double check",
    "backRankMate": "Back-rank mate", "smotheredMate": "Smothered mate", "anastasiaMate": "Anastasia's mate",
    "arabianMate": "Arabian mate", "bodenMate": "Boden's mate", "hookMate": "Hook mate",
    "doubleBishopMate": "Double-bishop mate", "capturingDefender": "Remove the defender", "deflection": "Deflection",
    "attraction": "Attraction", "trappedPiece": "Trapped piece", "promotion": "Promotion", "advancedPawn": "Advanced pawn",
    "pawnEndgame": "Pawn endgame", "rookEndgame": "Rook endgame", "sacrifice": "Sacrifice", "quietMove": "Quiet move",
    "defensiveMove": "Defensive move", "intermezzo": "In-between move", "clearance": "Clearance",
    "interference": "Interference", "xRayAttack": "X-ray attack", "zugzwang": "Zugzwang", "exposedKing": "Exposed king",
    "kingsideAttack": "Kingside attack", "attackingF2F7": "Attack on f2/f7", "endgame": "Endgame",
    "middlegame": "Middlegame", "opening": "Opening",
  ]

  public static func displayName(_ tag: String) -> String {
    names[tag] ?? tag.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
  }
}
