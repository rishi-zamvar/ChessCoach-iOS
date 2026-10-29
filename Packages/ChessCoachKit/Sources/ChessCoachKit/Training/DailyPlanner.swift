import Foundation

/// Per-skill weakness from the user's own games: exponentially decayed mistake
/// counts (half-life 14 days), normalized 0…1.
public struct WeaknessProfile: Equatable, Sendable {
  public var scores: [String: Double]
  /// Evidence per skill for the plan's "why" text, e.g. "allowed 3 forks".
  public var evidence: [String: Int]
  /// Share of analyzed user moves that hung material or allowed a tactic.
  public var safetyIssueRate: Double

  public init(scores: [String: Double] = [:], evidence: [String: Int] = [:], safetyIssueRate: Double = 0) {
    self.scores = scores
    self.evidence = evidence
    self.safetyIssueRate = safetyIssueRate
  }

  public static func from(mistakes: [MistakeRecord], userMoves: Int, now: Date, halfLifeDays: Double = 14) -> WeaknessProfile {
    var raw: [String: Double] = [:]
    var counts: [String: Int] = [:]
    var safety = 0
    for m in mistakes {
      let age = max(0, now.timeIntervalSince(m.endedAt) / 86_400)
      let weight = pow(0.5, age / halfLifeDays) * (m.label == "blunder" ? 1.5 : 1)
      var skills = Set<String>()
      let type = MistakeType(rawValue: m.mistakeType) ?? .positional
      let phase = GamePhaseKind(rawValue: m.phase) ?? .middlegame
      skills.insert(SkillCatalog.skill(forMistake: type, phase: phase))
      for motif in m.motifs.split(separator: ",").compactMap({ Motif(rawValue: String($0)) }) {
        if let skill = SkillCatalog.skill(forMotif: motif) { skills.insert(skill) }
      }
      if type == .hungMaterial || type == .allowedTactic { safety += 1 }
      for skill in skills {
        raw[skill, default: 0] += weight
        counts[skill, default: 0] += 1
      }
    }
    let top = raw.values.max() ?? 0
    let normalized = top > 0 ? raw.mapValues { $0 / top } : [:]
    return WeaknessProfile(
      scores: normalized, evidence: counts, safetyIssueRate: userMoves > 0 ? Double(safety) / Double(userMoves) : 0)
  }
}

/// One block of the daily session.
public struct PlanItem: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Sendable {
    case drill(DrillKind, count: Int)
    case speed(count: Int, rating: Int)
    case reviews(count: Int)
    case lesson(id: String)
    case themed(skillID: String, count: Int, rating: Int)
    case mixed(skillIDs: [String], count: Int, rating: Int)
    case ownMistakes(count: Int)
  }

  public var id: String
  public var title: String
  public var kind: Kind
  /// Why it's in today's plan (always shown).
  public var reason: String
  public var minutes: Double

  public init(id: String, title: String, kind: Kind, reason: String, minutes: Double) {
    self.id = id
    self.title = title
    self.kind = kind
    self.reason = reason
    self.minutes = minutes
  }
}

/// Splits the due reviews between the plan's two review blocks so neither can empty the other:
/// "Your mistakes" keeps the first `ownCount` own-game mistakes, "Reviews" gets everything else.
public enum ReviewSplit {
  public static func split(_ due: [ReviewItem], ownCount: Int) -> (reviews: [ReviewItem], own: [ReviewItem]) {
    let own = Array(due.filter { $0.kind == .mistake }.prefix(ownCount))
    let ownIDs = Set(own.map(\.id))
    return (due.filter { !ownIDs.contains($0.id) }, own)
  }
}

/// Everything the planner needs to know about the learner.
public struct LearnerState: Sendable {
  public var globalRating: Int
  public var skillRatings: [String: Glicko2]
  public var lastPracticed: [String: Date]
  public var masteredLessons: Set<String>
  public var dueReviews: Int
  public var ownMistakesAvailable: Int
  public var weakness: WeaknessProfile
  /// Yesterday's top focus skill (avoid repeating unless still the top game weakness).
  public var yesterdayFocus: String?
  /// Lessons whose skill appears in the curriculum (skill id → lesson id).
  public var lessonForSkill: [String: String]

  public init(
    globalRating: Int, skillRatings: [String: Glicko2] = [:], lastPracticed: [String: Date] = [:],
    masteredLessons: Set<String> = [], dueReviews: Int = 0, ownMistakesAvailable: Int = 0,
    weakness: WeaknessProfile = .init(), yesterdayFocus: String? = nil, lessonForSkill: [String: String] = [:]
  ) {
    self.globalRating = globalRating
    self.skillRatings = skillRatings
    self.lastPracticed = lastPracticed
    self.masteredLessons = masteredLessons
    self.dueReviews = dueReviews
    self.ownMistakesAvailable = ownMistakesAvailable
    self.weakness = weakness
    self.yesterdayFocus = yesterdayFocus
    self.lessonForSkill = lessonForSkill
  }
}

/// Builds the daily plan (research 01 §7.4): warm-up → reviews → focus on the top-2
/// skills → mixed set → own mistakes. Deterministic for a given state and day.
public struct DailyPlanner: Sendable {
  public struct Priority: Equatable, Sendable {
    public var skillID: String
    public var score: Double
    public var game: Double
    public var gap: Double
  }

  public var minutes: Double

  public init(minutes: Double = 15) {
    self.minutes = minutes
  }

  public func priorities(_ state: LearnerState, now: Date) -> [Priority] {
    let candidates = SkillCatalog.suggested(forRating: state.globalRating)
      .filter { state.weakness.scores[$0.id] ?? 0 > 0 || $0.band.lowerBound <= state.globalRating + 200 }
    return candidates.map { skill -> Priority in
      let rating = state.skillRatings[skill.id]
      let game = state.weakness.scores[skill.id] ?? 0
      let gap = rating.map { max(0, Double(state.globalRating) - $0.rating) / 200 } ?? 0.5
      let uncertainty = (rating?.deviation ?? 350) / 350
      let stale = state.lastPracticed[skill.id].map { min(1, now.timeIntervalSince($0) / 86_400 / 14) } ?? 1
      var score = 0.30 * game + 0.25 * min(1, gap) + 0.20 * skill.frequency + 0.15 * uncertainty + 0.10 * stale
      // Blunder-checking is the #1 lever below ~1400.
      if skill.id == "D1", state.weakness.safetyIssueRate > 0.05 { score += 0.3 }
      return Priority(skillID: skill.id, score: score, game: game, gap: gap)
    }
    .sorted { $0.score == $1.score ? $0.skillID < $1.skillID : $0.score > $1.score }
  }

  public func plan(for state: LearnerState, now: Date) -> [PlanItem] {
    var items: [PlanItem] = []
    let budget = minutes

    // 1. Warm-up (~10%).
    items.append(
      PlanItem(
        id: "warmup", title: "Board vision", kind: .drill(.coordinates, count: 10),
        reason: "Quick board-vision reps get your eyes ready.", minutes: budget * 0.07))
    items.append(
      PlanItem(
        id: "speed", title: "Quick warm-up", kind: .speed(count: 6, rating: max(400, state.globalRating - 500)),
        reason: "Easy puzzles at pace build pattern recognition.", minutes: budget * 0.06))

    // 2. Reviews (≤35%): what's due minus the mistakes "Your mistakes" keeps for itself (see ReviewSplit).
    let forReviews = state.dueReviews - Self.ownMistakesCount(state)
    if forReviews > 0 {
      let count = min(forReviews, max(1, Int(budget * 0.35 / 0.75)))
      items.append(
        PlanItem(
          id: "reviews", title: "Spaced review", kind: .reviews(count: count),
          reason: "\(forReviews) position\(forReviews == 1 ? "" : "s") due — reviewing at the right time makes them stick.",
          minutes: Double(count) * 0.75))
    }

    // 3. Focus block (~35%): top 2 skills.
    var ranked = priorities(state, now: now)
    if let yesterday = state.yesterdayFocus, ranked.first?.skillID == yesterday, ranked.count > 2,
      (ranked.first?.game ?? 0) < (ranked.dropFirst().map(\.game).max() ?? 0)
    {
      ranked.append(ranked.removeFirst())
    }
    var lessonPlanned = false
    for priority in ranked.prefix(2) {
      guard let skill = SkillCatalog.skill(priority.skillID) else { continue }
      // At most one lesson a day; its own practice set replaces the skill's themed block.
      if !lessonPlanned, let lessonID = state.lessonForSkill[skill.id], !state.masteredLessons.contains(lessonID) {
        lessonPlanned = true
        items.append(
          PlanItem(
            id: "lesson-\(lessonID)", title: "Lesson: \(skill.name)", kind: .lesson(id: lessonID),
            reason: reason(for: priority, skill: skill, state: state, teaching: true), minutes: 6))
        continue
      }
      let skillRating = Int(state.skillRatings[skill.id]?.rating ?? Double(state.globalRating))
      let kind: PlanItem.Kind =
        switch skill.source {
        case .drill(let drill): .drill(drill, count: 8)
        case .puzzles: .themed(skillID: skill.id, count: 6, rating: max(400, skillRating - 200))
        }
      items.append(
        PlanItem(
          id: "focus-\(skill.id)", title: skill.name, kind: kind,
          reason: reason(for: priority, skill: skill, state: state, teaching: false), minutes: 6 * Self.minutesPerPuzzle))
    }

    // 4. Mixed (~15%), weighted toward weaknesses.
    let mixSkills = ranked.prefix(5).map(\.skillID).filter { SkillCatalog.skill($0)?.themes.isEmpty == false }
    if !mixSkills.isEmpty {
      items.append(
        PlanItem(
          id: "mixed", title: "Mixed practice", kind: .mixed(skillIDs: mixSkills, count: 6, rating: max(400, state.globalRating - 150)),
          reason: "Mixing themes trains you to spot them in real games.", minutes: 6 * Self.minutesPerPuzzle))
    }

    // 5. Own mistakes (~10%).
    if state.ownMistakesAvailable > 0 {
      items.append(
        PlanItem(
          id: "own", title: "Your mistakes", kind: .ownMistakes(count: Self.ownMistakesCount(state)),
          reason: "Positions from your own games — the ones that cost you.", minutes: budget * 0.1))
    }
    return fill(items, budget: budget)
  }

  static func ownMistakesCount(_ state: LearnerState) -> Int { min(3, state.ownMistakesAvailable) }

  static let minutesPerPuzzle = 0.75

  /// Spends leftover time on more puzzles in the focus and mixed sets (no empty minutes
  /// when there are no reviews or lessons today).
  func fill(_ items: [PlanItem], budget: Double) -> [PlanItem] {
    var result = items
    var spare = budget - result.reduce(0) { $0 + $1.minutes }
    let growable = result.indices.filter {
      switch result[$0].kind {
      case .themed, .mixed: true
      default: false
      }
    }
    guard spare > Self.minutesPerPuzzle, !growable.isEmpty else { return result }
    var i = 0
    while spare >= Self.minutesPerPuzzle {
      let index = growable[i % growable.count]
      switch result[index].kind {
      case .themed(let skill, let count, let rating):
        result[index].kind = .themed(skillID: skill, count: count + 1, rating: rating)
      case .mixed(let skills, let count, let rating):
        result[index].kind = .mixed(skillIDs: skills, count: count + 1, rating: rating)
      default: break
      }
      result[index].minutes += Self.minutesPerPuzzle
      spare -= Self.minutesPerPuzzle
      i += 1
    }
    return result
  }

  private func reason(for priority: Priority, skill: Skill, state: LearnerState, teaching: Bool) -> String {
    if let count = state.weakness.evidence[skill.id], priority.game > 0.3 {
      let noun = count == 1 ? "time" : "times"
      return teaching
        ? "\(skill.name) came up \(count) \(noun) in your recent games — let's learn it properly."
        : "\(skill.name) cost you \(count) \(noun) in recent games."
    }
    if priority.gap > 0.5 { return "\(skill.name) is one of your weaker themes right now." }
    if teaching { return "New skill: \(skill.summary)" }
    return "\(skill.summary) It decides a lot of games at your level."
  }
}
