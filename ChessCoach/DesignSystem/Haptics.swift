import UIKit

/// The one ingress for haptics (spec W9 "Feel"); every call respects Settings → Haptics.
///   light: your move, chips, secondary buttons · medium: capture, main button · rigid: check
///   success: puzzle solved, feedback sent · warning: wrong move (gentler than error) · selection: scrubbing, pickers
@MainActor
enum Haptics {
  static let key = "feedback.haptics"
  static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

  static func light() { impact(.light) }
  static func medium() { impact(.medium) }
  static func heavy() { impact(.heavy) }
  static func soft() { impact(.soft) }
  static func rigid() { impact(.rigid) }
  static func selection() { if isEnabled { UISelectionFeedbackGenerator().selectionChanged() } }
  static func success() { notify(.success) }
  static func warning() { notify(.warning) }
  static func error() { notify(.error) }

  private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    if isEnabled { UIImpactFeedbackGenerator(style: style).impactOccurred() }
  }

  private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    if isEnabled { UINotificationFeedbackGenerator().notificationOccurred(type) }
  }
}
