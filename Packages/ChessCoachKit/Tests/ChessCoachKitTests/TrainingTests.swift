import ChessKit
import XCTest
@testable import ChessCoachKit

func makePuzzle(id: String = "p1", fen: String, moves: [String], rating: Int = 800, themes: [String] = ["mateIn1"]) -> Puzzle {
  Puzzle(id: id, fen: fen, moves: moves, rating: rating, rd: 75, popularity: 95, themes: themes, primaryTheme: themes[0], opening: nil)
}

/// Black's Kg8-h8 sets up White's back-rank mate (Rd8#, or Ra8# with two rooks).
let backRankFEN = "6k1/5ppp/8/8/8/8/5PPP/R2R2K1 b - - 0 1"

final class Glicko2Tests: XCTestCase {
  func test_givenGlickmanPaperExample_whenUpdated_thenMatchesPublishedResult() {
    let player = Glicko2(rating: 1500, deviation: 200, volatility: 0.06)
    let after = player.updated(with: [
      .init(opponentRating: 1400, opponentDeviation: 30, score: 1),
      .init(opponentRating: 1550, opponentDeviation: 100, score: 0),
      .init(opponentRating: 1700, opponentDeviation: 300, score: 0),
    ])
    XCTAssertEqual(after.rating, 1464.06, accuracy: 0.05)
    XCTAssertEqual(after.deviation, 151.52, accuracy: 0.05)
    XCTAssertEqual(after.volatility, 0.05999, accuracy: 0.0001)
  }

  func test_givenWinVsStrongerPuzzle_whenUpdated_thenRatingRisesAndDeviationShrinks() {
    let before = Glicko2(rating: 800, deviation: 250)
    let after = before.updated(vs: 1000, deviation: 75, score: 1)
    XCTAssertGreaterThan(after.rating, before.rating)
    XCTAssertLessThan(after.deviation, before.deviation)
  }

  func test_givenHalfWeight_whenUpdated_thenMovesHalfAsFar() {
    let before = Glicko2(rating: 800, deviation: 250)
    let full = before.updated(vs: 1000, deviation: 75, score: 1)
    let half = before.updated(vs: 1000, deviation: 75, score: 1, weight: 0.5)
    XCTAssertEqual(half.rating - before.rating, (full.rating - before.rating) / 2, accuracy: 0.001)
  }

  func test_givenEqualRatings_whenExpectedScore_thenHalf() {
    XCTAssertEqual(Glicko2(rating: 900).expectedScore(vs: 900, deviation: 80), 0.5, accuracy: 1e-9)
  }
}

final class PuzzleSessionTests: XCTestCase {
  func test_givenMateInOne_whenSetupThenExpectedMate_thenSolved() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"]))
    XCTAssertEqual(s.userColor, .white)
    XCTAssertEqual(s.playSetup(), "g8h8")
    XCTAssertEqual(s.submit(uci: "d1d8"), .solved)
    XCTAssertEqual(s.ratingScore, 1)
    XCTAssertEqual(s.grade(seconds: 5), .easy)
  }

  func test_givenMateInOne_whenDifferentMatingMove_thenAlsoAccepted() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"]))
    s.playSetup()
    XCTAssertEqual(s.submit(uci: "a1a8"), .solved)
  }

  func test_givenWrongMove_whenSubmitted_thenWrongAndBoardUnchangedThenRetryWorks() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"]))
    s.playSetup()
    let fen = s.game.position.fen
    XCTAssertEqual(s.submit(uci: "g1f1"), .wrong)
    XCTAssertEqual(s.game.position.fen, fen)
    XCTAssertEqual(s.submit(uci: "d1d8"), .solved)
    XCTAssertTrue(s.failedFirstTry)
    XCTAssertEqual(s.ratingScore, 0)
    XCTAssertEqual(s.grade(seconds: 5), .again)
  }

  func test_givenLongerPuzzle_whenCorrect_thenOpponentRepliesUntilSolved() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: GameSession.standardFEN, moves: ["e2e4", "e7e5", "g1f3", "b8c6"], themes: ["opening"]))
    s.playSetup()
    XCTAssertEqual(s.submit(uci: "e7e5"), .correct(reply: "g1f3"))
    XCTAssertEqual(s.submit(uci: "b8c6"), .solved)
  }

  func test_givenHints_whenRequested_thenThemeThenPieceThenMove() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"], themes: ["backRankMate", "mateIn1"]))
    s.playSetup()
    XCTAssertEqual(s.nextHint(), .theme("Back-rank mate"))
    XCTAssertEqual(s.nextHint(), .piece(Square("d1")))
    XCTAssertEqual(s.nextHint(), .move(from: Square("d1"), to: Square("d8")))
    XCTAssertEqual(s.submit(uci: "d1d8"), .solved)
    XCTAssertEqual(s.grade(seconds: 20), .again)
  }

  func test_givenOneHint_whenSolved_thenHalfScoreAndHard() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"]))
    s.playSetup()
    _ = s.nextHint()
    _ = s.submit(uci: "d1d8")
    XCTAssertEqual(s.ratingScore, 0.5)
    XCTAssertEqual(s.grade(seconds: 20), .hard)
  }

  func test_givenRetryPositionWithoutSetup_whenBestPlayed_thenSolved() {
    var s = PuzzleSession(puzzle: makePuzzle(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", moves: ["d1d8"]), hasSetupMove: false)
    XCTAssertNil(s.playSetup())
    XCTAssertEqual(s.userColor, .white)
    XCTAssertEqual(s.submit(uci: "d1d8"), .solved)
  }

  func test_givenThemeTags_whenDisplayed_thenFriendlyNames() {
    XCTAssertEqual(PuzzleThemes.displayName("mateIn2"), "Mate in 2")
    XCTAssertEqual(PuzzleThemes.displayName("someNewTag"), "Some New Tag")
  }
}

final class ReviewSchedulerTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func test_givenGrades_whenMapped_thenAgainHardGoodEasy() {
    XCTAssertEqual(AttemptGrade.from(solved: false, hintsUsed: 0, seconds: 5), .again)
    XCTAssertEqual(AttemptGrade.from(solved: true, hintsUsed: 3, seconds: 5), .again)
    XCTAssertEqual(AttemptGrade.from(solved: true, hintsUsed: 1, seconds: 5), .hard)
    XCTAssertEqual(AttemptGrade.from(solved: true, hintsUsed: 0, seconds: 90), .hard)
    XCTAssertEqual(AttemptGrade.from(solved: true, hintsUsed: 0, seconds: 30), .good)
    XCTAssertEqual(AttemptGrade.from(solved: true, hintsUsed: 0, seconds: 4), .easy)
  }

  func test_givenNewItem_whenReviewedGoodVsAgain_thenGoodIsDueLater() {
    let scheduler = ReviewScheduler()
    let item = scheduler.newItem(id: "x", kind: .puzzle, skillID: nil, fen: backRankFEN, solution: [], now: now)
    XCTAssertTrue(scheduler.isDue(item, at: now))
    let good = scheduler.review(item, grade: .good, now: now)
    let again = scheduler.review(item, grade: .again, now: now)
    XCTAssertGreaterThan(good.due, again.due)
    XCTAssertGreaterThan(good.due, now)
  }

  func test_givenRepeatedGoodReviews_whenScheduled_thenIntervalsGrow() {
    let scheduler = ReviewScheduler()
    var item = scheduler.newItem(id: "x", kind: .puzzle, skillID: nil, fen: backRankFEN, solution: [], now: now)
    var t = now
    var intervals: [TimeInterval] = []
    for _ in 0..<4 {
      item = scheduler.review(item, grade: .good, now: t)
      intervals.append(item.due.timeIntervalSince(t))
      t = item.due
    }
    XCTAssertEqual(intervals, intervals.sorted(), "\(intervals)")
    XCTAssertGreaterThan(intervals.last!, 86_400 * 3)
  }
}

final class PlannerTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func mistake(_ type: MistakeType, motifs: String, daysAgo: Double = 1) -> MistakeRecord {
    MistakeRecord(
      gameID: UUID().uuidString, ply: 10, label: "blunder", mistakeType: type.rawValue, motifs: motifs, phase: "middlegame",
      fen: GameSession.standardFEN, bestUCI: "e2e4", timeTrouble: false, endedAt: now.addingTimeInterval(-daysAgo * 86_400))
  }

  func test_givenForkMistakes_whenProfiled_thenForksTopAndSafetyIssues() {
    let profile = WeaknessProfile.from(
      mistakes: [mistake(.allowedTactic, motifs: "fork"), mistake(.allowedTactic, motifs: "fork"), mistake(.missedTactic, motifs: "pin")],
      userMoves: 30, now: now)
    XCTAssertEqual(profile.scores["C2"], 1)
    XCTAssertEqual(profile.evidence["C2"], 2)
    XCTAssertEqual(profile.safetyIssueRate, 2.0 / 30, accuracy: 1e-9)
  }

  func test_givenOldMistakes_whenProfiled_thenDecayed() {
    let fresh = WeaknessProfile.from(mistakes: [mistake(.missedTactic, motifs: "fork", daysAgo: 0), mistake(.missedTactic, motifs: "pin", daysAgo: 28)], userMoves: 10, now: now)
    // Same mistake type, 28 days = two half-lives older → a quarter of the weight.
    XCTAssertEqual((fresh.scores["C3"] ?? 0) / (fresh.scores["C2"] ?? 1), 0.25, accuracy: 0.01)
  }

  func test_givenForkWeakness_whenPlanned_thenForkFocusWithReasonAndLessonFirst() {
    let weakness = WeaknessProfile.from(mistakes: (0..<3).map { _ in mistake(.missedTactic, motifs: "fork") }, userMoves: 40, now: now)
    let state = LearnerState(globalRating: 500, weakness: weakness, lessonForSkill: ["C2": "C2"])
    let plan = DailyPlanner().plan(for: state, now: now)
    let lesson = plan.first { $0.kind == .lesson(id: "C2") }
    XCTAssertNotNil(lesson, "\(plan.map(\.title))")
    XCTAssertTrue(lesson?.reason.contains("3 times") ?? false, lesson?.reason ?? "")
    XCTAssertFalse(plan.contains { if case .themed(skillID: "C2", _, _) = $0.kind { true } else { false } }, "the lesson's practice replaces the themed block")
    XCTAssertEqual(plan.filter { if case .lesson = $0.kind { true } else { false } }.count, 1)
    XCTAssertLessThanOrEqual(plan.reduce(0) { $0 + $1.minutes }, 17)
  }

  func test_givenSafetyProblems_whenPlanned_thenBlunderCheckIsTopPriority() {
    let weakness = WeaknessProfile.from(mistakes: (0..<5).map { _ in mistake(.hungMaterial, motifs: "") }, userMoves: 40, now: now)
    let priorities = DailyPlanner().priorities(LearnerState(globalRating: 400, weakness: weakness), now: now)
    XCTAssertEqual(priorities.first?.skillID, "D1")
  }

  func test_givenDueReviewsAndMistakes_whenPlanned_thenReviewAndOwnMistakeBlocks() {
    let state = LearnerState(globalRating: 600, dueReviews: 4, ownMistakesAvailable: 7)
    let plan = DailyPlanner().plan(for: state, now: now)
    XCTAssertTrue(plan.contains { $0.kind == .reviews(count: 4) })
    XCTAssertTrue(plan.contains { $0.kind == .ownMistakes(count: 3) })
    XCTAssertEqual(plan.first?.id, "warmup")
    XCTAssertTrue(plan.allSatisfy { !$0.reason.isEmpty })
  }

  func test_givenNoReviews_whenPlanned_thenNoReviewBlockAndAroundFifteenMinutes() {
    let plan = DailyPlanner().plan(for: LearnerState(globalRating: 600), now: now)
    XCTAssertFalse(plan.contains { $0.id == "reviews" })
    XCTAssertEqual(plan.reduce(0) { $0 + $1.minutes }, 15, accuracy: 6)
  }

  func test_givenSameState_whenPlannedTwice_thenIdentical() {
    let state = LearnerState(globalRating: 700, dueReviews: 2)
    XCTAssertEqual(DailyPlanner().plan(for: state, now: now), DailyPlanner().plan(for: state, now: now))
  }
}

final class BoardVisionTests: XCTestCase {
  func test_givenScholarsPosition_whenChecksAndCapturesListed_thenIncludesQxf7() {
    let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
    let moves = BoardVision.checksAndCaptures(fen: fen)
    XCTAssertTrue(moves.contains("h5f7"))
    XCTAssertTrue(moves.contains("h5e5"))
    XCTAssertTrue(moves.contains("c4f7"))
    XCTAssertFalse(moves.contains("g1f3"))
  }

  func test_givenStartPosition_whenChecksAndCaptures_thenNone() {
    XCTAssertTrue(BoardVision.checksAndCaptures(fen: GameSession.standardFEN).isEmpty)
  }

  func test_givenPuzzle_whenSafetyQuestions_thenSetupMoveUnsafeAndSolutionSafe() {
    let qs = BoardVision.safetyQuestions(from: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"]))
    XCTAssertEqual(qs.map(\.isSafe), [false, true])
    XCTAssertEqual(qs[0].refutation, "d1d8")
  }

  func test_givenSeededRandom_whenCoordinateTargets_thenDeterministic() {
    XCTAssertEqual(BoardVision.coordinateTargets(count: 5, random: SeededRandom(seed: 1)),
                   BoardVision.coordinateTargets(count: 5, random: SeededRandom(seed: 1)))
  }
}

final class TrainingStoreTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  func test_givenSeededRatings_whenPuzzleSolved_thenPrimaryAndGlobalRiseAndAttemptLogged() throws {
    let store = TrainingStore(database: try AppDatabase.inMemory())
    try store.seedRatings(at: 500)
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"], rating: 700, themes: ["mateIn1", "backRankMate"]))
    s.playSetup()
    _ = s.submit(uci: "d1d8")
    let updated = try store.recordPuzzle(s, seconds: 8, now: now)
    XCTAssertGreaterThan(updated["B1"]!.rating, 500)
    XCTAssertGreaterThan(updated["B3"]!.rating, 500)
    XCTAssertLessThan(updated["B3"]!.rating - 500, updated["B1"]!.rating - 500, "secondary moves half")
    XCTAssertGreaterThan(try store.globalRating()!.rating, 500)
    XCTAssertEqual(try store.seenPuzzleIDs(since: now.addingTimeInterval(-60)), ["p1"])
    XCTAssertTrue(try store.reviewItems().isEmpty, "clean solves don't create reviews")
  }

  func test_givenFailedPuzzle_whenRecorded_thenReviewItemCreated() throws {
    let store = TrainingStore(database: try AppDatabase.inMemory())
    var s = PuzzleSession(puzzle: makePuzzle(fen: backRankFEN, moves: ["g8h8", "d1d8"]))
    s.playSetup()
    _ = s.submit(uci: "g1f1")
    _ = s.submit(uci: "d1d8")
    try store.recordPuzzle(s, seconds: 30, now: now)
    let items = try store.reviewItems()
    XCTAssertEqual(items.map(\.id), ["puzzle:p1"])
    XCTAssertEqual(items.first?.skillID, "B1")
    XCTAssertTrue(try store.dueReviews(at: now.addingTimeInterval(86_400 * 2)).count == 1)
  }

  func test_givenMistakes_whenAddedAsReviews_thenOncePerMoment() throws {
    let store = TrainingStore(database: try AppDatabase.inMemory())
    let m = MistakeRecord(
      gameID: "g", ply: 6, label: "blunder", mistakeType: "allowedTactic", motifs: "mate", phase: "opening",
      fen: GameSession.standardFEN, bestUCI: "e2e4", timeTrouble: false, endedAt: now)
    XCTAssertEqual(try store.addMistakeReviews([m, m], now: now), 1)
    XCTAssertEqual(try store.addMistakeReviews([m], now: now), 0)
    XCTAssertEqual(try store.reviewItems().first?.solution, ["e2e4"])
  }

  func test_givenLessonAttempts_whenRecorded_thenBestScoreAndPassedSticky() throws {
    let store = TrainingStore(database: try AppDatabase.inMemory())
    try store.recordLesson("C2", score: 8, passed: true, now: now)
    try store.recordLesson("C2", score: 5, passed: false, now: now)
    let progress = try store.lessonProgress()["C2"]!
    XCTAssertEqual(progress.bestScore, 8)
    XCTAssertTrue(progress.passed)
    XCTAssertEqual(progress.attempts, 2)
  }

  func test_givenAttemptsOnConsecutiveDays_whenStreak_thenCountsBackFromToday() throws {
    let store = TrainingStore(database: try AppDatabase.inMemory())
    for daysAgo in [0.0, 1, 2, 4] {
      var s = PuzzleSession(puzzle: makePuzzle(id: "p\(daysAgo)", fen: backRankFEN, moves: ["g8h8", "d1d8"]))
      s.playSetup()
      _ = s.submit(uci: "d1d8")
      try store.recordPuzzle(s, seconds: 5, now: now.addingTimeInterval(-daysAgo * 86_400))
    }
    XCTAssertEqual(try store.streak(now: now), 3)
    XCTAssertEqual(try store.streak(now: now.addingTimeInterval(86_400)), 3, "yesterday still counts")
    XCTAssertEqual(try store.streak(now: now.addingTimeInterval(3 * 86_400)), 0)
  }

  func test_givenProfile_whenSaved_thenRoundTrips() throws {
    let store = TrainingStore(database: try AppDatabase.inMemory())
    XCTAssertNil(try store.profile())
    let p = LearnerProfile(username: "Zammy009", style: .attacker, quizScore: 0.4, historyScore: nil, placementRating: 550, onboardedAt: now)
    try store.saveProfile(p)
    XCTAssertEqual(try store.profile(), p)
  }
}
