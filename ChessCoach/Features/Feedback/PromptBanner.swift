import ChessCoachKit
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

/// "Was this helpful?" under an explanation (spec W8): thumbs up/down, an optional line on what was
/// off, and the prompt budget (one per session, a 30-day pause after two dismissals).
struct ThumbsRow: View {
  let surface: String
  var context: [String: JSONValue] = [:]
  @Environment(AppEnvironment.self) private var env
  @State private var visible = false
  @State private var answered: Bool?
  @State private var note = ""
  @State private var sent = false

  var body: some View {
    Group {
      if sent || answered == true {
        Text("Thanks.").font(Typography.caption).foregroundStyle(Palette.textTertiary)
      } else if answered == false {
        HStack(spacing: Spacing.s) {
          TextField("What was off? (optional)", text: $note)
            .font(Typography.callout)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("thumbs-note")
          Button("Send") {
            Task { await env.feedback.thumb(surface: surface, up: false, note: note, context: context); sent = true }
          }
          .font(Typography.callout.weight(.semibold))
        }
      } else if visible {
        HStack(spacing: Spacing.m) {
          Text("Was this helpful?").font(Typography.caption).foregroundStyle(Palette.textSecondary)
          Button { answer(true) } label: { Image(systemName: "hand.thumbsup") }
            .accessibilityLabel("Helpful")
            .accessibilityIdentifier("thumbs-up")
          Button { answered = false } label: { Image(systemName: "hand.thumbsdown") }
            .accessibilityLabel("Not helpful")
            .accessibilityIdentifier("thumbs-down")
          Spacer()
          Button {
            env.feedback.promptBudget.dismissed(now: Date())
            visible = false
          } label: { Image(systemName: "xmark").font(Typography.caption) }
            .accessibilityLabel("Dismiss")
        }
        .font(Typography.body)
        .foregroundStyle(Palette.sage)
      }
    }
    .padding(.horizontal, Spacing.l)
    .frame(minHeight: visible || answered != nil ? 36 : 0)
    .onAppear {
      guard env.feedback.promptBudget.mayShow(now: Date(), timedPlay: false) else { return }
      env.feedback.promptBudget.shown(now: Date())
      visible = true
    }
  }

  private func answer(_ up: Bool) {
    answered = up
    Task { await env.feedback.thumb(surface: surface, up: up, note: nil, context: context) }
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
