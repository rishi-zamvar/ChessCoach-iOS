import FSRS
import Foundation

/// How an attempt went, mapped to an FSRS grade.
public enum AttemptGrade: String, Codable, Sendable {
  case again, hard, good, easy

  /// Wrong or fully revealed = again; any hint or slow = hard; quick and clean = easy.
  public static func from(solved: Bool, hintsUsed: Int, seconds: Double) -> AttemptGrade {
    if !solved || hintsUsed >= 3 { return .again }
    if hintsUsed > 0 || seconds > 60 { return .hard }
    if seconds < 10 { return .easy }
    return .good
  }

  var fsrs: Rating {
    switch self {
    case .again: .again
    case .hard: .hard
    case .good: .good
    case .easy: .easy
    }
  }
}

/// What a review card points at.
public enum ReviewKind: String, Codable, Sendable {
  /// A Lichess puzzle the user failed.
  case puzzle
  /// A critical moment from the user's own game ("retry this position").
  case mistake
  /// A lesson's key position.
  case lesson
}

public struct ReviewItem: Codable, Equatable, Sendable, Identifiable {
  /// e.g. `puzzle:00sHx`, `mistake:<game>:<ply>`.
  public var id: String
  public var kind: ReviewKind
  public var skillID: String?
  public var fen: String
  /// Expected solution (UCI) from `fen`.
  public var solution: [String]
  public var card: Card
  public var createdAt: Date

  public var due: Date { card.due }
}

/// FSRS-6 scheduling (swift-fsrs, default weights, 90% target retention).
public struct ReviewScheduler: Sendable {
  public init() {}

  private func engine() -> FSRS {
    FSRS(parameters: FSRSParameters(w: FSRSDefaults.defaultWv6))
  }

  public func newItem(id: String, kind: ReviewKind, skillID: String?, fen: String, solution: [String], now: Date) -> ReviewItem {
    ReviewItem(id: id, kind: kind, skillID: skillID, fen: fen, solution: solution, card: Card(due: now), createdAt: now)
  }

  /// The item after a review with `grade` at `now`.
  public func review(_ item: ReviewItem, grade: AttemptGrade, now: Date) -> ReviewItem {
    var updated = item
    if let log = try? engine().next(card: item.card, now: now, grade: grade.fsrs) {
      updated.card = log.card
    }
    return updated
  }

  public func isDue(_ item: ReviewItem, at now: Date) -> Bool { item.card.due <= now }

  /// Due items, most-forgotten (oldest due) first.
  public func dueQueue(_ items: [ReviewItem], at now: Date) -> [ReviewItem] {
    items.filter { isDue($0, at: now) }.sorted { $0.card.due < $1.card.due }
  }

  public func retrievability(_ item: ReviewItem, at now: Date) -> Double {
    engine().getRetrievability(card: item.card, now: now).number
  }
}
