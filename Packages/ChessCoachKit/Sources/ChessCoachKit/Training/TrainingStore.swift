import FSRS
import Foundation
import GRDB

/// The learner's onboarding profile.
public struct LearnerProfile: Codable, Equatable, Sendable {
  public enum Style: String, Codable, CaseIterable, Sendable {
    case attacker, tactician, positional, allRounder

    public var title: String {
      switch self {
      case .attacker: "Attacker"
      case .tactician: "Tactician"
      case .positional: "Positional"
      case .allRounder: "All-rounder"
      }
    }

    public var model: String {
      switch self {
      case .attacker: "Tal"
      case .tactician: "Kasparov"
      case .positional: "Carlsen"
      case .allRounder: "Anand"
      }
    }

    public var tagline: String {
      switch self {
      case .attacker: "Go for the king. Sacrifice for it."
      case .tactician: "Sharp positions. Punish every slip."
      case .positional: "Small edges, squeeze, win the endgame."
      case .allRounder: "A balanced mix — decide later."
      }
    }
  }

  public var username: String
  public var style: Style
  /// −1 (positional) … +1 (attacking) from the instinct quiz.
  public var quizScore: Double
  /// Same scale, from the user's games (nil until enough games).
  public var historyScore: Double?
  public var placementRating: Int
  public var onboardedAt: Date

  public init(username: String, style: Style, quizScore: Double, historyScore: Double?, placementRating: Int, onboardedAt: Date) {
    self.username = username
    self.style = style
    self.quizScore = quizScore
    self.historyScore = historyScore
    self.placementRating = placementRating
    self.onboardedAt = onboardedAt
  }
}

public struct LessonProgress: Codable, Equatable, Sendable {
  public var lessonID: String
  public var bestScore: Int
  public var attempts: Int
  public var passed: Bool
  public var updatedAt: Date
}

/// Persistence for training: skill ratings, review items, attempts, lessons, profile.
public struct TrainingStore: Sendable {
  let database: AppDatabase
  let scheduler = ReviewScheduler()
  public static let globalSkill = "global"

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Rows

  struct SkillRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "skill_rating"
    var skillID: String
    var rating: Double
    var deviation: Double
    var volatility: Double
    var attempts: Int
    var lastPracticed: Date?
  }

  struct ReviewRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "review_item"
    var id: String
    var kind: String
    var skillID: String?
    var fen: String
    var solution: String
    var card: String
    var createdAt: Date
    var due: Date

    init(_ item: ReviewItem) {
      id = item.id
      kind = item.kind.rawValue
      skillID = item.skillID
      fen = item.fen
      solution = item.solution.joined(separator: " ")
      card = (try? String(data: JSONEncoder().encode(item.card), encoding: .utf8)) ?? "{}"
      createdAt = item.createdAt
      due = item.card.due
    }

    var item: ReviewItem? {
      guard let card = try? JSONDecoder().decode(Card.self, from: Data(card.utf8)) else { return nil }
      return ReviewItem(
        id: id, kind: ReviewKind(rawValue: kind) ?? .puzzle, skillID: skillID, fen: fen,
        solution: solution.split(separator: " ").map(String.init), card: card, createdAt: createdAt)
    }
  }

  struct AttemptRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "attempt"
    var puzzleID: String
    var skillID: String?
    var solved: Bool
    var hints: Int
    var seconds: Double
    var at: Date
  }

  struct LessonRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "lesson_progress"
    var lessonID: String
    var bestScore: Int
    var attempts: Int
    var passed: Bool
    var updatedAt: Date
  }

  struct ProfileRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "profile"
    var id: Int = 1
    var json: String
  }

  // MARK: Skills

  public func skillRatings() throws -> [String: Glicko2] {
    try database.reader.read { db in
      Dictionary(uniqueKeysWithValues: try SkillRow.fetchAll(db).map {
        ($0.skillID, Glicko2(rating: $0.rating, deviation: $0.deviation, volatility: $0.volatility))
      })
    }
  }

  public func lastPracticed() throws -> [String: Date] {
    try database.reader.read { db in
      Dictionary(uniqueKeysWithValues: try SkillRow.fetchAll(db).compactMap { row in row.lastPracticed.map { (row.skillID, $0) } })
    }
  }

  public func globalRating() throws -> Glicko2? {
    try skillRatings()[Self.globalSkill]
  }

  /// Seeds every skill (and the global rating) at `rating` with high uncertainty.
  public func seedRatings(at rating: Int) throws {
    try database.writer.write { db in
      for id in SkillCatalog.all.map(\.id) + [Self.globalSkill] where try SkillRow.fetchOne(db, key: id) == nil {
        try SkillRow(skillID: id, rating: Double(rating), deviation: 250, volatility: 0.06, attempts: 0, lastPracticed: nil).insert(db)
      }
    }
  }

  /// Records a puzzle attempt: Glicko updates (primary skill full, other matching skills half,
  /// plus the global rating), the attempt row, and a review item when it went wrong.
  @discardableResult
  public func recordPuzzle(_ session: PuzzleSession, seconds: Double, now: Date) throws -> [String: Glicko2] {
    let puzzle = session.puzzle
    let score = session.ratingScore
    let primary = SkillCatalog.all.first { $0.themes.contains(puzzle.primaryTheme) }?.id
    let secondary = SkillCatalog.all.filter { skill in skill.id != primary && !Set(skill.themes).isDisjoint(with: puzzle.themes) }.map(\.id)
    let grade = session.grade(seconds: seconds)
    return try database.writer.write { db in
      var updated: [String: Glicko2] = [:]
      func update(_ id: String, weight: Double) throws {
        let row = try SkillRow.fetchOne(db, key: id)
          ?? SkillRow(skillID: id, rating: 1500, deviation: 350, volatility: 0.06, attempts: 0, lastPracticed: nil)
        let next = Glicko2(rating: row.rating, deviation: row.deviation, volatility: row.volatility)
          .updated(vs: Double(puzzle.rating), deviation: Double(puzzle.rd), score: score, weight: weight)
        try SkillRow(
          skillID: id, rating: next.rating, deviation: next.deviation, volatility: next.volatility,
          attempts: row.attempts + 1, lastPracticed: now
        ).save(db)
        updated[id] = next
      }
      if let primary { try update(primary, weight: 1) }
      for id in secondary { try update(id, weight: 0.5) }
      try update(Self.globalSkill, weight: 1)
      try AttemptRow(puzzleID: puzzle.id, skillID: primary, solved: score > 0, hints: session.hintsUsed, seconds: seconds, at: now).insert(db)

      let reviewID = "puzzle:\(puzzle.id)"
      if let existing = try ReviewRow.fetchOne(db, key: reviewID)?.item {
        try ReviewRow(scheduler.review(existing, grade: grade, now: now)).save(db)
      } else if grade == .again || grade == .hard {
        let item = scheduler.newItem(
          id: reviewID, kind: .puzzle, skillID: primary, fen: puzzle.fen, solution: puzzle.moves, now: now)
        try ReviewRow(scheduler.review(item, grade: grade, now: now)).insert(db)
      }
      return updated
    }
  }

  /// Puzzles attempted since `date` (excluded from new selections).
  public func seenPuzzleIDs(since date: Date) throws -> Set<String> {
    try database.reader.read { db in
      Set(try String.fetchAll(db, sql: "SELECT DISTINCT puzzleID FROM attempt WHERE at >= ?", arguments: [date]))
    }
  }

  /// Consecutive days (ending today or yesterday) with at least one training attempt.
  public func streak(now: Date, calendar: Calendar = .current) throws -> Int {
    let days = try database.reader.read { db in
      try Date.fetchAll(db, sql: "SELECT at FROM attempt WHERE at >= ? ORDER BY at DESC", arguments: [now.addingTimeInterval(-400 * 86_400)])
    }
    let practiced = Set(days.map { calendar.startOfDay(for: $0) })
    var day = calendar.startOfDay(for: now)
    if !practiced.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
    var count = 0
    while practiced.contains(day) {
      count += 1
      day = calendar.date(byAdding: .day, value: -1, to: day)!
    }
    return count
  }

  public func attemptsCount(since date: Date) throws -> Int {
    try database.reader.read { db in try AttemptRow.filter(Column("at") >= date).fetchCount(db) }
  }

  // MARK: Reviews

  public func reviewItems() throws -> [ReviewItem] {
    try database.reader.read { db in try ReviewRow.fetchAll(db).compactMap(\.item) }
  }

  public func dueReviews(at now: Date) throws -> [ReviewItem] {
    try database.reader.read { db in
      try ReviewRow.filter(Column("due") <= now).order(Column("due")).fetchAll(db).compactMap(\.item)
    }
  }

  public func review(_ item: ReviewItem, grade: AttemptGrade, now: Date) throws {
    try database.writer.write { db in
      try ReviewRow(scheduler.review(item, grade: grade, now: now)).save(db)
    }
  }

  /// Turns the user's analyzed game mistakes into "retry this position" review items.
  @discardableResult
  public func addMistakeReviews(_ mistakes: [MistakeRecord], now: Date) throws -> Int {
    try database.writer.write { db in
      var added = 0
      for m in mistakes {
        guard let best = m.bestUCI else { continue }
        let id = "mistake:\(m.gameID):\(m.ply)"
        guard try ReviewRow.fetchOne(db, key: id) == nil else { continue }
        let type = MistakeType(rawValue: m.mistakeType) ?? .positional
        let skill = SkillCatalog.skill(forMistake: type, phase: GamePhaseKind(rawValue: m.phase) ?? .middlegame)
        try ReviewRow(scheduler.newItem(id: id, kind: .mistake, skillID: skill, fen: m.fen, solution: [best], now: now)).insert(db)
        added += 1
      }
      return added
    }
  }

  /// Adds a review item unless one with this id already exists.
  @discardableResult
  public func addReviewIfMissing(id: String, kind: ReviewKind, skillID: String?, fen: String, solution: [String], now: Date) throws -> Bool {
    try database.writer.write { db in
      guard try ReviewRow.fetchOne(db, key: id) == nil else { return false }
      try ReviewRow(scheduler.newItem(id: id, kind: kind, skillID: skillID, fen: fen, solution: solution, now: now)).insert(db)
      return true
    }
  }

  // MARK: Lessons

  public func lessonProgress() throws -> [String: LessonProgress] {
    try database.reader.read { db in
      Dictionary(uniqueKeysWithValues: try LessonRow.fetchAll(db).map {
        ($0.lessonID, LessonProgress(lessonID: $0.lessonID, bestScore: $0.bestScore, attempts: $0.attempts, passed: $0.passed, updatedAt: $0.updatedAt))
      })
    }
  }

  public func recordLesson(_ lessonID: String, score: Int, passed: Bool, now: Date) throws {
    try database.writer.write { db in
      let old = try LessonRow.fetchOne(db, key: lessonID)
      try LessonRow(
        lessonID: lessonID, bestScore: max(score, old?.bestScore ?? 0), attempts: (old?.attempts ?? 0) + 1,
        passed: passed || (old?.passed ?? false), updatedAt: now
      ).save(db)
    }
  }

  // MARK: Profile

  public func profile() throws -> LearnerProfile? {
    try database.reader.read { db in
      try ProfileRow.fetchOne(db, key: 1).flatMap { try? JSONDecoder().decode(LearnerProfile.self, from: Data($0.json.utf8)) }
    }
  }

  /// Clears the onboarding profile (ratings, reviews and lessons stay).
  public func clearProfile() throws {
    _ = try database.writer.write { db in try ProfileRow.deleteAll(db) }
  }

  public func saveProfile(_ profile: LearnerProfile) throws {
    let json = String(data: try JSONEncoder().encode(profile), encoding: .utf8) ?? "{}"
    try database.writer.write { db in try ProfileRow(json: json).save(db) }
  }

  static func migrate(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("v3-training") { db in
      try db.create(table: "skill_rating") { t in
        t.primaryKey("skillID", .text)
        t.column("rating", .double).notNull()
        t.column("deviation", .double).notNull()
        t.column("volatility", .double).notNull()
        t.column("attempts", .integer).notNull()
        t.column("lastPracticed", .datetime)
      }
      try db.create(table: "review_item") { t in
        t.primaryKey("id", .text)
        t.column("kind", .text).notNull()
        t.column("skillID", .text)
        t.column("fen", .text).notNull()
        t.column("solution", .text).notNull()
        t.column("card", .text).notNull()
        t.column("createdAt", .datetime).notNull()
        t.column("due", .datetime).notNull().indexed()
      }
      try db.create(table: "attempt") { t in
        t.autoIncrementedPrimaryKey("rowid")
        t.column("puzzleID", .text).notNull().indexed()
        t.column("skillID", .text)
        t.column("solved", .boolean).notNull()
        t.column("hints", .integer).notNull()
        t.column("seconds", .double).notNull()
        t.column("at", .datetime).notNull().indexed()
      }
      try db.create(table: "lesson_progress") { t in
        t.primaryKey("lessonID", .text)
        t.column("bestScore", .integer).notNull()
        t.column("attempts", .integer).notNull()
        t.column("passed", .boolean).notNull()
        t.column("updatedAt", .datetime).notNull()
      }
      try db.create(table: "profile") { t in
        t.primaryKey("id", .integer)
        t.column("json", .text).notNull()
      }
    }
  }
}
