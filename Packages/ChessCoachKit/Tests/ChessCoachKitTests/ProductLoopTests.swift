import FSRS
import XCTest
@testable import ChessCoachKit

private func review(_ id: String, _ kind: ReviewKind) -> ReviewItem {
  ReviewItem(id: id, kind: kind, skillID: nil, fen: "8/8/8/8/8/8/8/K6k w - - 0 1", solution: ["a1a2"], card: Card(), createdAt: Date())
}

private func step(_ name: String, _ meta: [String: JSONValue] = [:], phase: StepPhase = .finish) -> StepEvent {
  StepEvent(id: UUID(), runID: UUID(), parentID: nil, step: name, phase: phase, metadata: meta)
}

final class ReviewSplitTests: XCTestCase {
  func test_givenReviewsBlockConsumedMistakes_whenMistakesBlockStarts_thenItsReservedTasksStillRun() {
    let due = [review("puzzle:a", .puzzle), review("mistake:g:1", .mistake), review("mistake:g:2", .mistake), review("mistake:g:3", .mistake)]
    let split = ReviewSplit.split(due, ownCount: 2)
    XCTAssertEqual(split.own.map(\.id), ["mistake:g:1", "mistake:g:2"])
    XCTAssertEqual(split.reviews.map(\.id), ["puzzle:a", "mistake:g:3"], "Reviews never takes the mistakes reserved for Your mistakes")
    XCTAssertTrue(Set(split.own.map(\.id)).isDisjoint(with: split.reviews.map(\.id)))
  }

  func test_givenOnlyMistakesDue_whenPlanned_thenNoReviewsBlockThatCouldEmptyYourMistakes() {
    let state = LearnerState(globalRating: 800, dueReviews: 2, ownMistakesAvailable: 2)
    let plan = DailyPlanner().plan(for: state, now: Date())
    XCTAssertNil(plan.first { $0.id == "reviews" })
    XCTAssertNotNil(plan.first { $0.id == "own" })
  }

  func test_givenPuzzleAndMistakeReviewsDue_whenPlanned_thenReviewsCountsOnlyWhatsLeftForIt() {
    let state = LearnerState(globalRating: 800, dueReviews: 5, ownMistakesAvailable: 4)
    let plan = DailyPlanner().plan(for: state, now: Date())
    guard case .reviews(let count)? = plan.first(where: { $0.id == "reviews" })?.kind else { return XCTFail("reviews block") }
    XCTAssertEqual(count, 2, "5 due minus the 3 Your mistakes keeps")
  }
}

final class AnalyticsTests: XCTestCase {
  func test_givenStepEvent_whenMapped_thenPostHogEventNameAndPropsMatchTaxonomy() {
    let mapped = AnalyticsEvent.map(step("training.puzzle", ["id": .string("00sHx"), "solved": .bool(true), "hints": .int(1), "seconds": .double(12.5)]))
    XCTAssertEqual(mapped?.name, "puzzle.done")
    XCTAssertEqual(mapped?.properties["first_move_ok"], .bool(true))
    XCTAssertEqual(mapped?.properties["secs"], .double(12.5))
    XCTAssertEqual(AnalyticsEvent.map(step("app.launch"))?.name, "app.open")
    XCTAssertEqual(AnalyticsEvent.map(step("plan.block_empty", ["kind": .string("own")]))?.name, "plan.block_empty")
    XCTAssertNil(AnalyticsEvent.map(step("analysis.ply", phase: .progress)), "progress ticks are noise")
    XCTAssertNil(AnalyticsEvent.map(step("engine.search")), "internal steps aren't product events")
    XCTAssertEqual(AnalyticsEvent.map(step("analysis.game", phase: .fail))?.name, "error")
  }

  func test_givenAICallAndGameSteps_whenMapped_thenCostKeptAndPerMoveNoiseDropped() {
    let ai = AnalyticsEvent.map(step("ai.call", ["model": .string("claude-haiku"), "costUSD": .double(0.0021), "purpose": .string("explain")]))
    XCTAssertEqual(ai?.name, "ai.call")
    XCTAssertEqual(ai?.properties["cost_usd"], .double(0.0021))
    XCTAssertEqual(AnalyticsEvent.map(step("game.end"))?.name, "game.end")
    XCTAssertNil(AnalyticsEvent.map(step("game.move")), "one event per move is too much")
    XCTAssertNil(AnalyticsEvent.map(step("game.botTurn")))
  }

  func test_givenSensitiveMetadata_whenMapped_thenScrubbed() {
    let mapped = AnalyticsEvent.map(step("screen.view", [
      "name": .string("today"), "api_key": .string("sk-ant-123"), "username": .string("Zammy009"),
      "text": .string("my question"), "note": .string(String(repeating: "x", count: 300)),
    ]))
    XCTAssertEqual(mapped?.properties, ["name": .string("today")])
  }

  func test_givenBasicTierOnly_whenEventsEmitted_thenNoIdentifyAndNoPersonProps() {
    let client = FakeAnalytics()
    let sink = AnalyticsSink(client: client, consent: { .basic })
    sink.record(step("app.launch"))
    sink.record(step("onboarding.complete", ["style": .string("tactician"), "rating": .int(700)]))
    XCTAssertEqual(client.captured.map(\.0), ["app.open", "onboarding.done"])
    XCTAssertEqual(client.identifyCalls, 0)
    XCTAssertNil(client.captured[1].1["username"])
  }

  func test_givenConsentOff_whenEventsEmitted_thenNothingSent() {
    let client = FakeAnalytics()
    AnalyticsSink(client: client, consent: { .off }).record(step("app.launch"))
    XCTAssertTrue(client.captured.isEmpty)
  }
}

final class FakeAnalytics: AnalyticsClient, @unchecked Sendable {
  var captured: [(String, [String: JSONValue])] = []
  var identifyCalls = 0
  func capture(_ name: String, properties: [String: JSONValue]) { captured.append((name, properties)) }
  func identify(_ id: String, properties: [String: JSONValue]) { identifyCalls += 1 }
  func reset() {}
}

final class FeedbackTests: XCTestCase {
  func test_givenFeedbackFromPuzzle_whenSubmitted_thenPayloadHasScreenFenBreadcrumbsAndNoAPIKey() {
    let crumbs = BreadcrumbSink(capacity: 3)
    for i in 0..<5 { crumbs.record(step("screen.view", ["name": .string("s\(i)")])) }
    crumbs.record(step("ai.settings", ["api_key": .string("sk-secret")]))
    let report = FeedbackReport.make(
      id: UUID(), category: .confusing, text: "  why was Nf3 wrong?  ", screen: "puzzle",
      context: ["fen": .string("8/8/8/8/8/8/8/K6k w - - 0 1"), "puzzle": .string("00sHx"), "key": .string("sk-secret")],
      breadcrumbs: crumbs.lines, build: "62", appVersion: "0.9.0", screenshotJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]), diagnostics: true)
    XCTAssertEqual(report.text, "why was Nf3 wrong?")
    XCTAssertEqual(report.screen, "puzzle")
    XCTAssertEqual(report.context["puzzle"], .string("00sHx"))
    XCTAssertNil(report.context["key"])
    XCTAssertEqual(report.breadcrumbs.count, 3, "ring buffer keeps the newest")
    XCTAssertEqual(report.breadcrumbs.last, "ai.settings")
    let json = String(decoding: try! JSONEncoder().encode(report), as: UTF8.self)
    XCTAssertFalse(json.contains("sk-secret"))
    XCTAssertTrue(json.contains("\"app_version\""))
    XCTAssertEqual(report.screenshot, Data([0xFF, 0xD8, 0xFF, 0xD9]).base64EncodedString())
  }

  func test_givenDiagnosticsOff_whenFeedbackSubmitted_thenOnlyTextCategoryAndScreenshotSent() {
    let report = FeedbackReport.make(
      id: UUID(), category: .bug, text: "stuck", screen: "today", context: ["fen": .string("x")],
      breadcrumbs: ["screen.view"], build: "62", appVersion: "0.9.0", screenshotJPEG: nil, diagnostics: false)
    XCTAssertTrue(report.context.isEmpty)
    XCTAssertTrue(report.breadcrumbs.isEmpty)
    XCTAssertEqual(report.screen, "", "the screen name is diagnostics too")
    XCTAssertNil(report.screenshot)
  }

  func test_givenOffline_whenFeedbackSubmitted_thenQueuedAndSentOnReconnect() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let outbox = FeedbackOutbox(directory: dir)
    let report = FeedbackReport.make(
      id: UUID(), category: .idea, text: "more lessons", screen: "train", context: [:], breadcrumbs: [],
      build: "62", appVersion: "0.9.0", screenshotJPEG: nil, diagnostics: true)
    try outbox.enqueue(report)
    var online = false
    var sent: [UUID] = []
    await outbox.flush { r in
      guard online else { throw URLError(.notConnectedToInternet) }
      sent.append(r.id)
    }
    XCTAssertEqual(outbox.pending().map(\.id), [report.id], "kept while offline")
    online = true
    await outbox.flush { r in sent.append(r.id) }
    XCTAssertEqual(sent, [report.id])
    XCTAssertTrue(outbox.pending().isEmpty)
    try outbox.enqueue(report)
    XCTAssertEqual(outbox.pending().count, 1, "enqueueing the same id twice keeps one copy")
  }
}
