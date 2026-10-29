import SwiftUI

/// Shake anywhere: `UIWindow.motionEnded` (FeedbackCenter.swift) posts this when no text field
/// claimed the shake for undo.
extension Notification.Name {
  static let deviceDidShake = Notification.Name("knightlight.device.didShake")
}

extension View {
  func onShake(perform action: @escaping () -> Void) -> some View {
    onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in action() }
  }
}
