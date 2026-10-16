import Foundation

/// Move labels (our own names/icons; thresholds follow chess.com's published
/// expected-points model, with a stricter, Maia-gated Brilliant).
public enum MoveClass: String, Codable, CaseIterable, Sendable {
  case brilliant, great, best, excellent, good, book, forced, inaccuracy, mistake, miss, blunder

  public var displayName: String {
    switch self {
    case .brilliant: "Brilliant"
    case .great: "Great"
    case .best: "Best"
    case .excellent: "Excellent"
    case .good: "Good"
    case .book: "Book"
    case .forced: "Forced"
    case .inaccuracy: "Inaccuracy"
    case .mistake: "Mistake"
    case .miss: "Miss"
    case .blunder: "Blunder"
    }
  }

  /// Annotation glyph shown on the board and move list.
  public var glyph: String {
    switch self {
    case .brilliant: "!!"
    case .great: "!"
    case .best: "★"
    case .excellent: "👍"
    case .good: "✓"
    case .book: "📖"
    case .forced: "→"
    case .inaccuracy: "?!"
    case .mistake: "?"
    case .miss: "✗"
    case .blunder: "??"
    }
  }

  /// Moves worth stopping on in a review.
  public var isCritical: Bool {
    [.brilliant, .great, .mistake, .miss, .blunder].contains(self)
  }

  public var isError: Bool { [.inaccuracy, .mistake, .miss, .blunder].contains(self) }
}

/// Everything the classifier needs about one ply. All win values are the
/// mover's expected points (0…1) from the mover's perspective.
public struct PlyEval: Sendable, Equatable {
  public var legalMoveCount: Int
  public var isBook: Bool
  /// Expected points of the engine's best move (before playing).
  public var bestEP: Double
  /// Expected points of the second-best move, if MultiPV ≥ 2.
  public var secondBestEP: Double?
  /// Expected points after the move actually played.
  public var playedEP: Double
  public var playedIsBest: Bool
  /// The move gives up material (static exchange says it loses ≥ 2 points).
  public var isSacrifice: Bool
  /// Maia's probability for the played move at the user's rating, if known.
  public var maiaProbability: Double?
  /// Expected points the opponent threw away on the previous move.
  public var opponentPreviousLoss: Double?

  public init(
    legalMoveCount: Int, isBook: Bool, bestEP: Double, secondBestEP: Double?, playedEP: Double,
    playedIsBest: Bool, isSacrifice: Bool = false, maiaProbability: Double? = nil, opponentPreviousLoss: Double? = nil
  ) {
    self.legalMoveCount = legalMoveCount
    self.isBook = isBook
    self.bestEP = bestEP
    self.secondBestEP = secondBestEP
    self.playedEP = playedEP
    self.playedIsBest = playedIsBest
    self.isSacrifice = isSacrifice
    self.maiaProbability = maiaProbability
    self.opponentPreviousLoss = opponentPreviousLoss
  }

  /// Expected points lost by the played move (never negative).
  public var loss: Double { playedIsBest ? 0 : max(0, bestEP - playedEP) }
}

public enum MoveClassifier {
  public static let thresholds = (excellent: 0.02, good: 0.05, inaccuracy: 0.10, mistake: 0.20)

  public static func classify(_ e: PlyEval) -> MoveClass {
    if e.legalMoveCount == 1 { return .forced }
    if e.isBook { return .book }

    let loss = e.loss
    let nearBest = e.playedIsBest || loss <= thresholds.excellent + epsilon

    if nearBest, e.isSacrifice, bucket(e.playedEP) != .losing, let p = e.maiaProbability, p < 0.10 {
      return .brilliant
    }
    // "Great" = the only move that holds the result; cashing in on the opponent's
    // blunder (gift ≥ 0.20) is just "Best", as on chess.com.
    let punishingBlunder = (e.opponentPreviousLoss ?? 0) >= 0.20
    if e.playedIsBest, !punishingBlunder, let second = e.secondBestEP, e.bestEP - second >= 0.10, bucket(e.bestEP) != bucket(second) {
      return .great
    }
    if let gift = e.opponentPreviousLoss, gift >= 0.10, loss >= gift / 2, loss > thresholds.good {
      return .miss
    }

    var label = base(loss: loss, isBest: e.playedIsBest)
    // A position that was already decided can't be thrown away by one move.
    let decided = e.bestEP <= 0.05 || e.bestEP >= 0.95
    if decided, label == .mistake || label == .blunder {
      label = e.bestEP >= 0.95 && e.playedEP < 0.5 ? label : .inaccuracy
    }
    return label
  }

  /// Tolerance so that a loss of exactly 0.02 (which is 0.020000000000000018 in
  /// floating point) still lands in the inclusive band.
  static let epsilon = 1e-9

  static func base(loss: Double, isBest: Bool) -> MoveClass {
    if isBest || loss <= 0.0001 { return .best }
    if loss <= thresholds.excellent + epsilon { return .excellent }
    if loss <= thresholds.good + epsilon { return .good }
    if loss <= thresholds.inaccuracy + epsilon { return .inaccuracy }
    if loss <= thresholds.mistake + epsilon { return .mistake }
    return .blunder
  }

  enum Bucket { case losing, equal, winning }

  static func bucket(_ ep: Double) -> Bucket {
    ep >= 0.6 ? .winning : (ep <= 0.4 ? .losing : .equal)
  }
}
