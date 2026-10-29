import SwiftUI
import UIKit

/// A one-line banner above everything (full-screen boards included) in its own pass-through window:
/// "Report a problem with this screen?" after a screenshot, or "Fixed in this build".
@MainActor
enum PromptBanner {
  private static var window: PassthroughWindow?

  static func show(_ prompt: FeedbackCenter.Prompt, center: FeedbackCenter, onShowReports: @escaping () -> Void) {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
    let w = window ?? PassthroughWindow(windowScene: scene)
    w.windowLevel = .alert
    w.backgroundColor = .clear
    let host = UIHostingController(rootView: BannerView(text: prompt.text) {
      hide()
      switch prompt.action {
      case .reportScreen: center.open(source: "screenshot")
      case .showReports: onShowReports()
      }
    } dismiss: { hide() })
    host.view.backgroundColor = .clear
    w.rootViewController = host
    w.isHidden = false
    window = w
    Task {
      try? await Task.sleep(for: .seconds(6))
      hide()
    }
  }

  static func hide() {
    window?.isHidden = true
    window?.rootViewController = nil
  }
}

/// Only the banner takes touches; everything else falls through to the app.
final class PassthroughWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit == rootViewController?.view ? nil : hit
  }
}

private struct BannerView: View {
  let text: String
  let action: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack {
      HStack(spacing: Spacing.m) {
        Image(systemName: "bubble.left.and.exclamationmark.bubble.right").foregroundStyle(Palette.sage)
          .accessibilityHidden(true)
        Button(action: action) {
          Text(text).font(Typography.callout.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prompt-banner")
        Button(action: dismiss) { Image(systemName: "xmark").font(Typography.caption.weight(.bold)) }
          .foregroundStyle(Palette.textSecondary)
          .accessibilityLabel("Dismiss")
      }
      .padding(.horizontal, Spacing.l)
      .padding(.vertical, Spacing.m)
      .background(Capsule().fill(Palette.surfaceRaised))
      .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.75))
      .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
      .padding(.horizontal, Spacing.l)
      Spacer()
    }
    .padding(.top, Spacing.s)
  }
}
