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
