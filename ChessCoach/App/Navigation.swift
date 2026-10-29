import ChessCoachKit
import SwiftUI

/// Lets any screen switch the root tab (Today's "Play a game" → Play). Set by RootView.
struct SelectTabAction {
  var action: @MainActor (RootView.Tab) -> Void = { _ in }
  @MainActor func callAsFunction(_ tab: RootView.Tab) { action(tab) }
}

extension EnvironmentValues {
  @Entry var selectTab = SelectTabAction()
}

extension PlanItem {
  /// Short block kind for analytics (`plan.block_*{kind}`).
  var kindName: String {
    switch kind {
    case .drill: "drill"
    case .speed: "speed"
    case .reviews: "reviews"
    case .lesson: "lesson"
    case .themed: "themed"
    case .mixed: "mixed"
    case .ownMistakes: "own"
    }
  }
}
