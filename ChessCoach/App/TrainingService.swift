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
  /// The skill the planner ranks first today (the completion card's bonus set).
  private(set) var topSkillID: String?
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
    // The plan is fixed for the day (built once); finishing blocks doesn't reshuffle it.
    let built = planner.plan(for: state, now: now)
    let dayKey = Self.completedKey(for: now).replacingOccurrences(of: "completed", with: "ids")
    if let ids = UserDefaults.standard.stringArray(forKey: dayKey), !ids.isEmpty {
      let byID = Dictionary(built.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
      let stored = UserDefaults.standard.data(forKey: dayKey + ".items").flatMap { try? JSONDecoder().decode([StoredPlanItem].self, from: $0) } ?? []
      plan = ids.compactMap { id in byID[id] ?? stored.first { $0.id == id }?.item }
    } else {
      plan = built
      UserDefaults.standard.set(built.map(\.id), forKey: dayKey)
      if let data = try? JSONEncoder().encode(built.map(StoredPlanItem.init)) { UserDefaults.standard.set(data, forKey: dayKey + ".items") }
      UserDefaults.standard.set(UserDefaults.standard.string(forKey: "plan.todayFocus"), forKey: "plan.yesterdayFocus")
      UserDefaults.standard.set(built.first { $0.id.hasPrefix("focus-") }.map { String($0.id.dropFirst(6)) }, forKey: "plan.todayFocus")
    }
    let rating = globalRating
    let style = profile?.style.title ?? "All-rounder"
    let ranked = planner.priorities(state, now: now)
    topSkillID = ranked.first { SkillCatalog.skill($0.skillID)?.themes.isEmpty == false }?.skillID
    let real = realRating.map { "chess.com rapid about \($0)" } ?? "no chess.com games yet"
    let focus = ranked.prefix(3).compactMap { p in
      SkillCatalog.skill(p.skillID).map { skill in
        "\(skill.name)\(weakness.evidence[skill.id].map { " (missed \($0)× in recent games)" } ?? "")"
      }
    }.joined(separator: ", ")
    env.learnerBrief = { "Puzzle rating about \(rating), \(real), style \(style). Working on: \(focus)." }
    let ratings = skillRatings.mapValues(\.rating)
    env.puzzleRatings = { ratings }
    let styleID = profile?.style.rawValue ?? "allRounder"
    env.repertoireStyle = { styleID }
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

  /// Retake onboarding (Settings).
  func resetProfile() {
    try? store.clearProfile()
    env.telemetry.event("onboarding.reset")
    refresh()
  }

  /// The user's real chess.com rating (median of recent games), if any are imported.
  var realRating: Int? { RatingAnchor.realRating((try? env.gameStore.recent(limit: 50)) ?? []) }

  /// Pulls the overall rating back to the real one when it has drifted far (>150) from it.
  func anchorToRealRating() {
    guard profile != nil, RatingAnchor.needsRecalibration(current: globalRating, real: realRating), let real = realRating else { return }
    env.telemetry.event("rating.anchor", metadata: ["from": .int(globalRating), "to": .int(real)])
    try? store.setGlobalRating(real)
    refresh()
  }

  func completeOnboarding(_ profile: LearnerProfile) {
    var profile = profile
    profile.placementRating = RatingAnchor.blend(placement: profile.placementRating, real: realRating)
    try? store.saveProfile(profile)
    try? store.seedRatings(at: profile.placementRating)  // only seeds skills that have no rating yet
    try? store.setGlobalRating(profile.placementRating)  // a retake's placement counts
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
      return splitReviews(now: now).reviews.prefix(count).compactMap(task(for:))
    case .ownMistakes(let count):
      return splitReviews(now: now).own.prefix(count).compactMap(task(for:))
    }
  }

  /// Due reviews divided between today's two review blocks, so one can't empty the other.
  private func splitReviews(now: Date) -> (reviews: [ReviewItem], own: [ReviewItem]) {
    let own = plan.compactMap { if case .ownMistakes(let n) = $0.kind { n } else { nil } }.first ?? 0
    return ReviewSplit.split((try? store.dueReviews(at: now)) ?? [], ownCount: own)
  }

  /// A bonus set of five on today's top skill (offered once the plan is done).
  func bonusTasks() -> (title: String, tasks: [TrainingTask])? {
    guard let id = topSkillID, let skill = SkillCatalog.skill(id) else { return nil }
    let rating = Int(skillRatings[id]?.rating ?? Double(globalRating))
    return ("Bonus: \(skill.name)", puzzleTasks(themes: skill.themes, rating: max(400, rating - 100), count: 5))
  }

  var isPlanDone: Bool { !plan.isEmpty && plan.allSatisfy { completedToday.contains($0.id) } }

  /// Streak with finished plan blocks counting too (not just puzzles), one missed day a week forgiven.
  func streak(now: Date = Date()) -> Int {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let blockDays = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> Date? in
      guard key.hasPrefix("plan.completed."), let done = value as? [String], !done.isEmpty else { return nil }
      return f.date(from: String(key.dropFirst("plan.completed.".count)))
    }
    return (try? store.streak(now: now, alsoPracticed: Set(blockDays))) ?? 0
  }

  func puzzlesToday(now: Date = Date()) -> Int {
    (try? store.attemptsCount(since: Calendar.current.startOfDay(for: now))) ?? 0
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
    return due.prefix(limit).compactMap(task(for:))
  }

  /// Positions from your games where you made the same kind of mistake, taken one game at a
  /// time (newest games first) so a session spreads across games instead of one bad game.
  func patternTasks(key: String, limit: Int = 6) -> [TrainingTask] {
    let mistakes = ((try? env.analysisStore.mistakes(inPattern: key)) ?? []).filter { $0.bestUCI != nil }
    var queues = Dictionary(grouping: mistakes, by: \.gameID).values.map { $0.sorted { $0.ply < $1.ply } }
      .sorted { ($0.first?.endedAt ?? .distantPast) > ($1.first?.endedAt ?? .distantPast) }
    var picked: [MistakeRecord] = []
    while picked.count < limit, queues.contains(where: { !$0.isEmpty }) {
      for i in queues.indices where !queues[i].isEmpty && picked.count < limit {
        picked.append(queues[i].removeFirst())
      }
    }
    _ = try? store.addMistakeReviews(picked, now: Date())
    let items = Dictionary(((try? store.reviewItems()) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    return picked.compactMap { items["mistake:\($0.gameID):\($0.ply)"] }.compactMap(task(for:))
  }

  /// For a review from your own game: why the move you played was a mistake.
  func insight(for item: ReviewItem) -> MoveInsight? {
    guard item.kind == .mistake, let colon = item.id.lastIndex(of: ":"), let ply = Int(item.id[item.id.index(after: colon)...]) else { return nil }
    let gameID = String(item.id["mistake:".endIndex..<colon])
    guard let analysis = try? env.analysisStore.analysis(gameID: gameID), ply >= 1, ply <= analysis.moves.count else { return nil }
    return MoveInsight.make(analysis.moves[ply - 1])
  }

  private func task(for item: ReviewItem) -> TrainingTask? {
    switch item.kind {
    case .puzzle:
      let id = String(item.id.dropFirst("puzzle:".count))
      return (try? puzzles?.puzzle(id: id)).flatMap { $0 }.map { TrainingTask.review(item, $0) }
    case .mistake, .lesson:
      // The theme feeds the first hint, so it must be a real tactic name, never the skill code ("D1").
      let theme = item.skillID.flatMap { SkillCatalog.skill($0)?.themes.first } ?? ""
      let puzzle = Puzzle(
        id: item.id, fen: item.fen, moves: item.solution, rating: globalRating, rd: 100, popularity: 100,
        themes: theme.isEmpty ? [] : [theme], primaryTheme: theme, opening: nil)
      return .review(item, puzzle)
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
  func record(puzzle session: some PuzzleOutcome, seconds: Double) -> RatingChange {
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

  func record(review item: ReviewItem, session: some PuzzleOutcome, seconds: Double) {
    let grade = session.grade(seconds: seconds)
    try? store.review(item, grade: grade, now: Date())
    env.telemetry.event("training.review", metadata: ["id": .string(item.id), "grade": .string(grade.rawValue)])
  }

  func recordLesson(_ lesson: Lesson, score: Int, of total: Int) {
    let passed = lesson.isPassed(score: score, total: total)
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

  func markDone(_ item: PlanItem, empty: Bool = false, now: Date = Date()) {
    guard !completedToday.contains(item.id) else { return }
    completedToday.insert(item.id)
    UserDefaults.standard.set(Array(completedToday), forKey: Self.completedKey(for: now))
    env.telemetry.event(empty ? "plan.block_empty" : "plan.block_done", metadata: ["kind": .string(item.kindName)])
    if isPlanDone { env.telemetry.event("plan.done", metadata: ["blocks": .int(plan.count)]) }
    revision += 1
  }

  /// The next block still to do after `item` (or the first one left).
  func nextBlock(after item: PlanItem?) -> PlanItem? {
    let left = plan.filter { !completedToday.contains($0.id) && $0.id != item?.id }
    guard let item, let at = plan.firstIndex(where: { $0.id == item.id }) else { return left.first }
    return left.first { (plan.firstIndex(of: $0) ?? 0) > at } ?? left.first
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

/// A plan block persisted for the day (so it can be shown even if today's rebuild differs).
private struct StoredPlanItem: Codable {
  var id: String
  var title: String
  var reason: String
  var minutes: Double
  var kind: String
  var a: String
  var n: Int
  var r: Int

  init(_ item: PlanItem) {
    id = item.id
    title = item.title
    reason = item.reason
    minutes = item.minutes
    switch item.kind {
    case .drill(let d, let c): (kind, a, n, r) = ("drill", d.rawValue, c, 0)
    case .speed(let c, let rating): (kind, a, n, r) = ("speed", "", c, rating)
    case .reviews(let c): (kind, a, n, r) = ("reviews", "", c, 0)
    case .lesson(let id): (kind, a, n, r) = ("lesson", id, 0, 0)
    case .themed(let s, let c, let rating): (kind, a, n, r) = ("themed", s, c, rating)
    case .mixed(let ss, let c, let rating): (kind, a, n, r) = ("mixed", ss.joined(separator: ","), c, rating)
    case .ownMistakes(let c): (kind, a, n, r) = ("own", "", c, 0)
    }
  }

  var item: PlanItem? {
    let k: PlanItem.Kind
    switch kind {
    case "drill": guard let d = DrillKind(rawValue: a) else { return nil }; k = .drill(d, count: n)
    case "speed": k = .speed(count: n, rating: r)
    case "reviews": k = .reviews(count: n)
    case "lesson": k = .lesson(id: a)
    case "themed": k = .themed(skillID: a, count: n, rating: r)
    case "mixed": k = .mixed(skillIDs: a.split(separator: ",").map(String.init), count: n, rating: r)
    case "own": k = .ownMistakes(count: n)
    default: return nil
    }
    return PlanItem(id: id, title: title, kind: k, reason: reason, minutes: minutes)
  }
}
