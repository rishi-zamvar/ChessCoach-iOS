import Foundation

/// The taught lessons (`Resources/curriculum.json`, validated by `scripts/validate_curriculum.py`).
public struct Curriculum: Codable, Sendable, Equatable {
  public var version: Int
  public var lessons: [Lesson]

  public static let shared: Curriculum = {
    guard let url = Bundle.module.url(forResource: "curriculum", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { fatalError("curriculum.json missing from ChessCoachKit bundle") }
    do {
      return try JSONDecoder().decode(Curriculum.self, from: data)
    } catch {
      fatalError("curriculum.json is invalid: \(error)")
    }
  }()

  public func lesson(id: String) -> Lesson? { lessons.first { $0.id == id } }

  /// Lessons whose band contains `rating`, in curriculum order.
  public func lessons(forRating rating: Int) -> [Lesson] {
    lessons.filter { $0.band.count == 2 && $0.band[0] <= rating && rating <= $0.band[1] }
  }
}

public struct Lesson: Codable, Sendable, Equatable, Identifiable {
  /// Mastery check used everywhere (no practice → not passed).
  public func isPassed(score: Int, total: Int) -> Bool {
    total > 0 && score * mastery.of >= mastery.required * total
  }

  public var id: String
  public var skill: String
  public var title: String
  /// `[low, high]` rating band.
  public var band: [Int]
  public var prerequisites: [String]
  public var idea: String
  public var keyPoints: [String]
  public var worked: WorkedExample
  public var faded: FadedExample
  public var practice: Practice
  public var mastery: Mastery
}

/// The app plays `moves` from `fen`; `narration[i]` and `arrows[i]` belong to `moves[i]`.
public struct WorkedExample: Codable, Sendable, Equatable {
  public var fen: String
  public var moves: [String]
  public var narration: [String]
  public var arrows: [[LessonArrow]]
  public var intro: String?
}

/// `solution` is the user's moves, alternating with the forced replies (user, reply, user…).
public struct FadedExample: Codable, Sendable, Equatable {
  public var fen: String
  public var solution: [String]
  public var prompt: String
  public var hint: String
  public var explanation: String
}

public struct LessonArrow: Codable, Sendable, Equatable {
  public var from: String
  public var to: String
  /// green = solution, red = threat, blue = hint/support.
  public var color: String
}

public struct Practice: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable {
    case puzzles, coordinates, checksCaptures, safeMove, playout
  }

  public enum Goal: String, Codable, Sendable {
    case mate, draw, promote
  }

  public var kind: Kind
  public var count: Int
  /// Lichess theme tags (puzzles only).
  public var themes: [String]?
  /// `[low, high]` puzzle rating range (puzzles only).
  public var rating: [Int]?
  /// Start position (playout only).
  public var fen: String?
  public var goal: Goal?
}

public struct Mastery: Codable, Sendable, Equatable {
  public var required: Int
  public var of: Int
}
