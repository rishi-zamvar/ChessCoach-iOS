import ChessKit
import Foundation

/// What the store needs to record any puzzle attempt (instant or coach mode).
public protocol PuzzleOutcome: Sendable {
  var puzzle: Puzzle { get }
  var ratingScore: Double { get }
  var hintsUsed: Int { get }
  func grade(seconds: Double) -> AttemptGrade
}

extension PuzzleSession: PuzzleOutcome {}

/// Coach mode (spec W3): every move is accepted and the opponent answers with its best move.
/// When the line ends, if any of your moves lost too much you're asked to find which one,
/// then to find the better move from there. The app supplies each move's loss (expected points,
/// from the engine) and the opponent's replies; this type only keeps score.
public struct CoachPuzzleRun: PuzzleOutcome {
  public enum Phase: Equatable, Sendable {
    case playing
    /// Every move held up.
    case solved
    /// "One of your moves was a mistake. Can you find which?"
    case findMistake
    /// Rewound to just before the mistake: find the better move.
    case fixMistake(fen: String)
    case done
  }

  public enum Pick: Equatable, Sendable {
    case found(fen: String)
    /// "Not that one — the position was still fine after it."
    case notThat
    /// Two wrong picks: the mistake is shown.
    case revealed(index: Int)
  }

  public enum Grade: String, Equatable, Sendable {
    case clean, selfFound, assisted, revealed
  }

  public struct UserMove: Equatable, Sendable {
    public var uci: String
    public var san: String
    public var fenBefore: String
    /// Expected points lost by this move (0…1).
    public var loss: Double
  }

  /// Loss at or above this is a mistake (the game-review "mistake" line).
  public static let mistakeLoss = MoveClassifier.thresholds.inaccuracy

  public let puzzle: Puzzle
  public let hasSetupMove: Bool
  public private(set) var game: GameSession
  public private(set) var phase: Phase = .playing
  public private(set) var moves: [UserMove] = []
  public private(set) var hintsUsed = 0
  private var wrongPicks = 0
  private var mistakeRevealed = false
  private var fixRevealed = false

  public init(puzzle: Puzzle, hasSetupMove: Bool = true) {
    self.puzzle = puzzle
    self.hasSetupMove = hasSetupMove
    game = GameSession(startFEN: puzzle.fen)
  }

  @discardableResult
  public mutating func playSetup() -> String? {
    guard hasSetupMove, game.history.isEmpty, let first = puzzle.moves.first else { return nil }
    game.apply(uci: first)
    return first
  }

  public var userColor: Piece.Color {
    let side = Position(fen: puzzle.fen)?.sideToMove ?? .white
    return hasSetupMove ? side.opposite : side
  }

  /// Your moves in the solution, plus one so a slip near the end still gets played out.
  public var userMovesAllowed: Int {
    let afterSetup = puzzle.moves.count - (hasSetupMove ? 1 : 0)
    return (afterSetup + 1) / 2 + 1
  }

  public var awaitingOpponent: Bool { phase == .playing && game.sideToMove != userColor }

  /// The first move that lost too much, if any.
  public var mistakeIndex: Int? { moves.firstIndex { $0.loss >= Self.mistakeLoss } }

  /// Plays your move (any legal move). Returns false if illegal or not your turn.
  @discardableResult
  public mutating func play(uci: String, loss: Double) -> Bool {
    guard phase == .playing, game.sideToMove == userColor else { return false }
    let before = game.position.fen
    var trial = game
    guard case .applied(let played) = trial.apply(uci: uci) else { return false }
    game = trial
    moves.append(UserMove(uci: played.uci, san: played.san, fenBefore: before, loss: loss))
    if game.isOver || moves.count >= userMovesAllowed { finish() }
    return true
  }

  public mutating func opponentPlays(uci: String) {
    guard awaitingOpponent else { return }
    game.apply(uci: uci)
    if game.isOver { finish() }
  }

  private mutating func finish() {
    phase = mistakeIndex == nil ? .solved : .findMistake
  }

  /// Your guess at which of your moves was the mistake.
  public mutating func pick(_ index: Int) -> Pick {
    guard phase == .findMistake, let mistake = mistakeIndex, moves.indices.contains(index) else { return .notThat }
    if index == mistake {
      phase = .fixMistake(fen: moves[mistake].fenBefore)
      return .found(fen: moves[mistake].fenBefore)
    }
    wrongPicks += 1
    guard wrongPicks >= 2 else { return .notThat }
    mistakeRevealed = true
    phase = .fixMistake(fen: moves[mistake].fenBefore)
    return .revealed(index: mistake)
  }

  public mutating func useHint() { hintsUsed += 1 }

  /// You found the better move.
  public mutating func fixed() {
    if case .fixMistake = phase { phase = .done }
  }

  /// You asked to see the better move.
  public mutating func revealFix() {
    guard case .fixMistake = phase else { return }
    fixRevealed = true
    phase = .done
  }

  public var coachGrade: Grade {
    if mistakeIndex == nil { return .clean }
    if fixRevealed { return .revealed }
    // One wrong guess then finding it yourself still counts as finding it.
    if mistakeRevealed || hintsUsed >= 2 { return .assisted }
    return .selfFound
  }

  /// First-move correctness, so ratings stay comparable with instant mode.
  public var ratingScore: Double { (moves.first?.loss ?? 1) < Self.mistakeLoss ? 1 : 0 }

  public func grade(seconds: Double) -> AttemptGrade {
    switch coachGrade {
    case .clean: AttemptGrade.from(solved: true, hintsUsed: 0, seconds: seconds)
    case .selfFound, .assisted: .hard
    case .revealed: .again
    }
  }
}
