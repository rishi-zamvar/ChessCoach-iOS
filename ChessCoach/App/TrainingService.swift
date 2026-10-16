import ChessCoachKit
import Foundation
import Observation

/// One thing to do in a training run.
enum TrainingTask: Identifiable, Equatable {
  case puzzle(Puzzle)
  /// A spaced-repetition review (failed puzzle or own-game mistake).
  case review(ReviewItem, Puzzle)
  case drill(DrillKind)
  case lesson(Lesson)

  var id: String {
    switch self {
    case .puzzle(let p): "puzzle:\(p.id)"
    case .review(let r, _): "review:\(r.id)"
    case .drill(let d): "drill:\(d.rawValue)"
    case .lesson(let l): "lesson:\(l.id)"
    }
  }
}

/// App-side training coordinator: profile, ratings, today's plan, task queues, recording.
@MainActor
@Observable
final class TrainingService {
  private(set) var profile: LearnerProfile?
  private(set) var plan: [PlanItem] = []
  private(set) var completedToday: Set<String> = []
  private(set) var skillRatings: [String: Glicko2] = [:]
  private(set) var lessonProgress: [String: LessonProgress] = [:]
  private(set) var dueReviewCount = 0
  private(set) var revision = 0

  @ObservationIgnored let store: TrainingStore
  @ObservationIgnored let puzzles: PuzzleStore?
  @ObservationIgnored private let env: AppEnvironment
  @ObservationIgnored private let planner = DailyPlanner()

  init(env: AppEnvironment) {
    self.env = env
    store = TrainingStore(database: env.database)
    puzzles = PuzzleStore.bundled()
    refresh()
  }

  var needsOnboarding: Bool { profile == nil }
  var globalRating: Int { Int(skillRatings[TrainingStore.globalSkill]?.rating ?? Double(profile?.placementRating ?? 400)) }
  var planMinutesLeft: Double { plan.filter { !completedToday.contains($0.id) }.reduce(0) { $0 + $1.minutes } }

  // MARK: - Refresh

  func refresh(now: Date = Date()) {
    profile = try? store.profile()
    skillRatings = (try? store.skillRatings()) ?? [:]
    lessonProgress = (try? store.lessonProgress()) ?? [:]
    let mistakes = (try? env.analysisStore.mistakes()) ?? []
    _ = try? store.addMistakeReviews(mistakes, now: now)
    let due = (try? store.dueReviews(at: now)) ?? []
    dueReviewCount = due.count
    completedToday = Self.loadCompleted(for: now)

    let analyzedMoves = max(1, ((try? env.analysisStore.analyzedGameIDs().count) ?? 0) * 30)
    let weakness = WeaknessProfile.from(mistakes: mistakes, userMoves: analyzedMoves, now: now)
    // First not-yet-passed lesson per planner skill (curriculum skills that aren't
    // planner skills teach the nearest one).
    var lessonForSkill: [String: String] = [:]
    let passed = Set(lessonProgress.values.filter(\.passed).map(\.lessonID))
    for lesson in Curriculum.shared.lessons where !passed.contains(lesson.id) {
      let skill = Self.lessonSkillAlias[lesson.skill] ?? lesson.skill
      if lessonForSkill[skill] == nil { lessonForSkill[skill] = lesson.id }
    }
    let state = LearnerState(
      globalRating: globalRating, skillRatings: skillRatings, lastPracticed: (try? store.lastPracticed()) ?? [:],
      masteredLessons: Set(lessonProgress.values.filter(\.passed).map(\.lessonID)), dueReviews: due.count,
      ownMistakesAvailable: due.filter { $0.kind == .mistake }.count, weakness: weakness,
      yesterdayFocus: UserDefaults.standard.string(forKey: "plan.yesterdayFocus"), lessonForSkill: lessonForSkill)
    plan = planner.plan(for: state, now: now)
    env.telemetry.event(
      "training.plan",
      metadata: ["items": .int(plan.count), "due": .int(due.count), "rating": .int(globalRating),
        "focus": .string(plan.filter { $0.id.hasPrefix("focus-") }.map(\.id).joined(separator: ","))])
    revision += 1
  }

  static let lessonSkillAlias: [String: String] = [
    "A3": "C1", "A6": "C1", "A4": "D2", "A5": "D1", "B2": "B1", "E2": "E1", "E3": "E1", "F1": "D1",
  ]

  // MARK: - Onboarding

  func completeOnboarding(_ profile: LearnerProfile) {
    try? store.saveProfile(profile)
    try? store.seedRatings(at: profile.placementRating)
    env.telemetry.event("onboarding.complete", metadata: ["style": .string(profile.style.rawValue), "rating": .int(profile.placementRating)])
    refresh()
  }

  // MARK: - Tasks

  /// The task queue for one plan item.
  func tasks(for item: PlanItem, now: Date = Date()) -> [TrainingTask] {
    switch item.kind {
    case .drill(let kind, _):
      return [.drill(kind)]
    case .lesson(let id):
      return Curriculum.shared.lesson(id: id).map { [.lesson($0)] } ?? []
    case .speed(let count, let rating):
      return puzzleTasks(themes: ["mateIn1", "hangingPiece", "fork"], rating: rating, count: count)
    case .themed(let skillID, let count, let rating):
      return puzzleTasks(themes: SkillCatalog.skill(skillID)?.themes ?? [], rating: rating, count: count)
    case .mixed(let skillIDs, let count, let rating):
      let themes = skillIDs.flatMap { SkillCatalog.skill($0)?.themes ?? [] }
      return puzzleTasks(themes: themes, rating: rating, count: count)
    case .reviews(let count):
      return reviewTasks(kind: nil, limit: count, now: now)
    case .ownMistakes(let count):
      return reviewTasks(kind: .mistake, limit: count, now: now)
    }
  }

  /// Puzzles spread across `themes`, excluding anything seen in the last 90 days.
  func puzzleTasks(themes: [String], rating: Int, count: Int) -> [TrainingTask] {
    guard let puzzles else { return [] }
    let seen = (try? store.seenPuzzleIDs(since: Date().addingTimeInterval(-90 * 86_400))) ?? []
    var picked: [Puzzle] = []
    var excluded = seen
    let pool = themes.isEmpty ? [nil] : themes.map(Optional.some)
    var round = 0
    while picked.count < count, round < count * 2 {
      let theme = pool[round % pool.count]
      if let next = try? puzzles.puzzles(theme: theme, around: rating, excluding: excluded, limit: 1).first {
        picked.append(next)
        excluded.insert(next.id)
      }
      round += 1
    }
    return picked.map(TrainingTask.puzzle)
  }

  func reviewTasks(kind: ReviewKind?, limit: Int, now: Date) -> [TrainingTask] {
    let due = ((try? store.dueReviews(at: now)) ?? []).filter { kind == nil || $0.kind == kind }
    return due.prefix(limit).compactMap { item -> TrainingTask? in
      switch item.kind {
      case .puzzle:
        let id = String(item.id.dropFirst("puzzle:".count))
        return (try? puzzles?.puzzle(id: id)).flatMap { $0 }.map { TrainingTask.review(item, $0) }
      case .mistake, .lesson:
        let puzzle = Puzzle(
          id: item.id, fen: item.fen, moves: item.solution, rating: globalRating, rd: 100, popularity: 100,
          themes: [item.skillID ?? "mistake"], primaryTheme: item.skillID ?? "mistake", opening: nil)
        return .review(item, puzzle)
      }
    }
  }

  // MARK: - Recording

  struct RatingChange: Equatable {
    var before: Int
    var after: Int
    var delta: Int { after - before }
  }

  /// Records a rated puzzle; returns the global rating change.
  @discardableResult
  func record(puzzle session: PuzzleSession, seconds: Double) -> RatingChange {
    let before = globalRating
    let updated = (try? store.recordPuzzle(session, seconds: seconds, now: Date())) ?? [:]
    if let global = updated[TrainingStore.globalSkill] { skillRatings[TrainingStore.globalSkill] = global }
    for (id, rating) in updated { skillRatings[id] = rating }
    env.telemetry.event(
      "training.puzzle",
      metadata: ["id": .string(session.puzzle.id), "solved": .bool(session.ratingScore > 0), "hints": .int(session.hintsUsed),
        "seconds": .double(seconds), "rating": .int(globalRating)])
    return RatingChange(before: before, after: globalRating)
  }

  func record(review item: ReviewItem, session: PuzzleSession, seconds: Double) {
    let grade = session.grade(seconds: seconds)
    try? store.review(item, grade: grade, now: Date())
    env.telemetry.event("training.review", metadata: ["id": .string(item.id), "grade": .string(grade.rawValue)])
  }

  func recordLesson(_ lesson: Lesson, score: Int, of total: Int) {
    let passed = score >= lesson.mastery.required * total / max(1, lesson.mastery.of)
    try? store.recordLesson(lesson.id, score: score, passed: passed, now: Date())
    lessonProgress = (try? store.lessonProgress()) ?? lessonProgress
    env.telemetry.event("training.lesson", metadata: ["id": .string(lesson.id), "score": .int(score), "passed": .bool(passed)])
  }

  func recordDrill(_ kind: DrillKind, correct: Int, total: Int, seconds: Double) {
    env.telemetry.event(
      "training.drill",
      metadata: ["kind": .string(kind.rawValue), "correct": .int(correct), "total": .int(total), "seconds": .double(seconds)])
  }

  /// A missed repertoire move becomes a review card ("play your move here").
  func addOpeningReview(repertoire: Repertoire, node: RepertoireNode) {
    _ = try? store.addReviewIfMissing(
      id: "opening:\(repertoire.fileName):\(node.id)", kind: .lesson, skillID: "F1",
      fen: repertoire.fenBefore(node), solution: [node.uci], now: Date())
  }

  func markDone(_ item: PlanItem, now: Date = Date()) {
    completedToday.insert(item.id)
    UserDefaults.standard.set(Array(completedToday), forKey: Self.completedKey(for: now))
    if item.id.hasPrefix("focus-") {
      UserDefaults.standard.set(String(item.id.dropFirst("focus-".count)), forKey: "plan.yesterdayFocus")
    }
    revision += 1
  }

  private static func completedKey(for date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return "plan.completed.\(f.string(from: date))"
  }

  private static func loadCompleted(for date: Date) -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: completedKey(for: date)) ?? [])
  }
}
