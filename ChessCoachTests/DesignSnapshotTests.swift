import ChessCoachKit
import SnapshotTesting
import SwiftUI
import XCTest
@testable import ChessCoach

/// Screens and components in the four looks every screen must survive (spec W9):
/// light, dark, the largest accessibility text size, and dark with Increase Contrast.
/// First run records references (in __Snapshots__); later runs compare against them.
@MainActor
final class DesignSnapshotTests: XCTestCase {
  static let looks: [(String, UITraitCollection)] = [
    ("light", UITraitCollection(userInterfaceStyle: .light)),
    ("dark", UITraitCollection(userInterfaceStyle: .dark)),
    ("ax5", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .light), .init(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)])),
    ("darkHC", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .high)])),
  ]

  func snapshotAllLooks<V: View>(_ view: V, named name: String, height: CGFloat = 900, file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
    for (look, traits) in Self.looks {
      let size = CGSize(width: 393, height: look == "ax5" ? height * 2 : height)
      assertSnapshot(
        of: view.frame(width: size.width, height: size.height),
        as: .image(precision: 0.98, perceptualPrecision: 0.97, layout: .fixed(width: size.width, height: size.height), traits: traits),
        named: "\(name)-\(look)", file: file, testName: testName, line: line)
    }
  }

  func test_givenEveryScreen_whenSnapshotInLightDarkAX5HighContrast_thenMatchesReference_components() {
    snapshotAllLooks(ComponentGallery(), named: "components")
  }

  /// A fresh learner with today's plan (optionally all done). Clears today's stored plan afterwards.
  private func appEnvironment(planDone: Bool = false) -> (AppEnvironment, AnalysisService, TrainingService) {
    clearToday()
    addTeardownBlock { @MainActor in self.clearToday() }
    let env = AppEnvironment(inMemory: true)
    let training = TrainingService(env: env)
    training.completeOnboarding(
      LearnerProfile(username: "snap", style: .allRounder, quizScore: 0, historyScore: nil, placementRating: 700, onboardedAt: Date()))
    if planDone { training.plan.forEach { training.markDone($0) } }
    return (env, AnalysisService(env: env), training)
  }

  private func clearToday() {
    for key in ["completed", "ids"] {
      UserDefaults.standard.removeObject(forKey: "plan.\(key).\(Self.day)")
      UserDefaults.standard.removeObject(forKey: "plan.\(key).\(Self.day).items")
    }
  }

  /// Date-dependent screens: rendered for visual QA (ScreenRenders/), not compared.
  private func render<V: View>(_ view: V, named name: String, height: CGFloat = 1400) {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ScreenRenders")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (look, traits) in Self.looks {
      let host = UIHostingController(rootView: view.frame(width: 393, height: look == "ax5" ? height * 2 : height))
      let size = CGSize(width: 393, height: look == "ax5" ? height * 2 : height)
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
      window.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
      window.traitOverrides.accessibilityContrast = traits.accessibilityContrast
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.layoutIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
      try? image.pngData()?.write(to: dir.appendingPathComponent("\(name)-\(look).png"))
    }
  }

  func test_givenFreshLearner_whenTodayRenders_thenPlanWithStartButton() {
    let (env, analysis, training) = appEnvironment()
    XCTAssertFalse(training.plan.isEmpty)
    XCTAssertNotNil(training.nextBlock(after: nil))
    render(TodayView().environment(env).environment(analysis).environment(training), named: "today")
  }

  func test_givenPlanDone_whenTodayRenders_thenCompletionCardWithThreeCTAs() {
    let (env, analysis, training) = appEnvironment(planDone: true)
    XCTAssertTrue(training.isPlanDone)
    XCTAssertNil(training.nextBlock(after: nil), "nothing left, so no Start button")
    XCTAssertEqual(training.bonusTasks()?.tasks.count, 5, "the bonus set is offered")
    render(TodayView().environment(env).environment(analysis).environment(training), named: "today-done")
  }

  func test_givenBlockDone_whenAskingNext_thenTheFollowingUnfinishedBlock() {
    let (_, _, training) = appEnvironment()
    let first = training.plan[0]
    training.markDone(first)
    XCTAssertEqual(training.nextBlock(after: first)?.id, training.plan[1].id)
  }

  func test_givenEveryScreen_whenSnapshotInLightDarkAX5HighContrast_thenMatchesReference_feedbackSheet() {
    let env = AppEnvironment(inMemory: true)
    UserDefaults.standard.removeObject(forKey: FeedbackDraft.draftKey)
    var draft = FeedbackDraft(screen: "today", context: ["plan_done": .bool(true)], screenshot: UIImage(systemName: "sun.max"))
    draft.category = .bug
    draft.text = "Cannot progress beyond this page."
    snapshotAllLooks(FeedbackSheet(center: env.feedback, draft: draft), named: "feedback")
  }

  static var day: String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
  }
}

/// Every design-system component on one page.
struct ComponentGallery: View {
  var body: some View {
    ZStack {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Eyebrow(text: "Today · 28 Oct")
          Text("Today").font(Typography.display).foregroundStyle(Palette.textPrimary)
          SectionHeader(title: "Mixed practice", eyebrow: "Focus", subtitle: "Five puzzles on forks, about 5 minutes")
          Card {
            Text("Your knight on f3 was doing real work. Why move it twice?")
              .font(Typography.coachSpeech).foregroundStyle(Palette.textPrimary)
          }
          PrimaryButton(title: "Next: Mixed practice", action: {}, icon: "play.fill")
          SecondaryButton(title: "Back to Today", action: {})
          HStack { ActionButton(title: "Retry", systemImage: "arrow.counterclockwise") {}; ActionButton(title: "Next", systemImage: "arrow.right", prominent: true) {} }
          HStack { Chip(title: "Bug", isSelected: true) {}; Chip(title: "Idea") {}; StepperButton(direction: .plus) {}; GlassIconButton(systemImage: "arrow.left.arrow.right", label: "Flip") {} }
          HStack { ForEach(MoveQuality.allCases, id: \.self) { QualityBadge(quality: $0) } }
          Text("1,552  Nxe5 Bxf7+").font(Typography.numeric).foregroundStyle(Palette.textPrimary)
          EmptyState(title: "No games yet", message: "Finished games show up here.", systemImage: "clock")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxl)
      }
    }
  }
}
