import XCTest
@testable import ChessCoachKit

/// M4: streak freeze, prompt budget, App Store review timing, plain block names.
final class StreakTests: XCTestCase {
  let cal = Calendar(identifier: .gregorian)
  func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))! }

  func test_givenOneMissedDayThisWeek_whenCounting_thenFreezeKeepsTheStreak() {
    // Practised 20, 21, (missed 22), 23, 24 → still a 4-day streak on the 24th.
    let days: Set<Date> = [day(20), day(21), day(23), day(24)]
    XCTAssertEqual(StreakCounter.count(practiced: days, now: day(24), calendar: cal), 4)
  }

  func test_givenTwoMissedDaysInAWeek_whenCounting_thenStreakBreaks() {
    let days: Set<Date> = [day(19), day(22), day(24)]
    XCTAssertEqual(StreakCounter.count(practiced: days, now: day(24), calendar: cal), 2, "22 + 24 with 23 frozen; 21 and 20 both missed")
  }

  func test_givenNothingToday_whenCounting_thenYesterdaysStreakStillShows() {
    XCTAssertEqual(StreakCounter.count(practiced: [day(22), day(23)], now: day(24), calendar: cal), 2)
  }

  func test_givenPlanBlocks_whenNamed_thenPlainWords() {
    let plan = DailyPlanner().plan(for: LearnerState(globalRating: 800, dueReviews: 2), now: Date())
    let titles = plan.map(\.title)
    XCTAssertTrue(titles.contains("Quick warm-up"))
    XCTAssertTrue(titles.contains("Spaced review"))
    XCTAssertFalse(titles.contains("Speed set"))
  }
}

final class PromptPolicyTests: XCTestCase {
  func test_givenPromptShownThisSession_whenNextPromptDue_thenSuppressed() {
    var budget = PromptBudget()
    let now = Date()
    XCTAssertTrue(budget.mayShow(now: now, timedPlay: false))
    budget.shown(now: now)
    XCTAssertFalse(budget.mayShow(now: now, timedPlay: false), "one prompt per session")
    budget.newSession()
    XCTAssertTrue(budget.mayShow(now: now, timedPlay: false))
    XCTAssertFalse(budget.mayShow(now: now, timedPlay: true), "never during timed play")
  }

  func test_givenTwoDismissalsInARow_whenAsked_thenPausedForThirtyDays() {
    var budget = PromptBudget()
    let now = Date()
    budget.shown(now: now); budget.dismissed(now: now); budget.newSession()
    budget.shown(now: now); budget.dismissed(now: now); budget.newSession()
    XCTAssertFalse(budget.mayShow(now: now.addingTimeInterval(29 * 86_400), timedPlay: false))
    XCTAssertTrue(budget.mayShow(now: now.addingTimeInterval(31 * 86_400), timedPlay: false))
  }

  func test_givenAnswer_whenRecorded_thenDismissStreakResets() {
    var budget = PromptBudget()
    let now = Date()
    budget.shown(now: now); budget.dismissed(now: now); budget.newSession()
    budget.shown(now: now); budget.answered(); budget.newSession()
    budget.shown(now: now); budget.dismissed(now: now); budget.newSession()
    XCTAssertTrue(budget.mayShow(now: now, timedPlay: false))
  }

  func test_givenSuccessAfterAWeek_whenDecidingReviewPrompt_thenAskOncePerVersion() {
    let install = Date().addingTimeInterval(-8 * 86_400)
    var policy = ReviewPromptPolicy(installedAt: install)
    XCTAssertTrue(policy.shouldAsk(version: "0.9.0", now: Date()))
    policy.asked(version: "0.9.0")
    XCTAssertFalse(policy.shouldAsk(version: "0.9.0", now: Date()))
    XCTAssertTrue(policy.shouldAsk(version: "0.9.1", now: Date()))
  }

  func test_givenTooSoonOrUnhappy_whenDecidingReviewPrompt_thenDoNotAsk() {
    XCTAssertFalse(ReviewPromptPolicy(installedAt: Date()).shouldAsk(version: "0.9.0", now: Date()), "under 7 days")
    var unhappy = ReviewPromptPolicy(installedAt: Date().addingTimeInterval(-30 * 86_400))
    unhappy.negativeSignal(now: Date())
    XCTAssertFalse(unhappy.shouldAsk(version: "0.9.0", now: Date()), "never right after a thumbs down or bug report")
  }
}
