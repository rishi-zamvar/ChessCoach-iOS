import ChessCoachKit
import ChessKit
import StoreKit
import SwiftUI

/// End-of-game card shown over the board.
struct ResultCard: View {
  let result: GameResult
  let userColor: Piece.Color
  let opponentName: String
  let onReview: () -> Void
  let onNewGame: () -> Void
  let onDone: () -> Void
  @Environment(AppEnvironment.self) private var env
  @Environment(\.requestReview) private var requestReview

  private var outcome: (title: String, icon: String, tint: Color) {
    switch result.winner {
    case nil: ("Draw", "equal.circle.fill", Palette.textSecondary)
    case userColor: ("You Won!", "trophy.fill", Palette.success)
    default: ("\(opponentName) Won", "flag.fill", Palette.danger)
    }
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.45).ignoresSafeArea()
        .onTapGesture(perform: onDone)
        .onAppear(perform: maybeAskForRating)
      VStack(spacing: Spacing.l) {
        Image(systemName: outcome.icon)
          .font(Typography.symbol(40))
          .foregroundStyle(outcome.tint)
        VStack(spacing: Spacing.xs) {
          Text(outcome.title)
            .font(.system(.title).weight(.bold))
            .foregroundStyle(Palette.textPrimary)
            .accessibilityIdentifier("result-title")
          Text("by \(result.termination.displayName.lowercased())")
            .font(.system(.subheadline).weight(.medium))
            .foregroundStyle(Palette.textSecondary)
        }
        VStack(spacing: Spacing.s) {
          ActionButton(title: "Game Review", systemImage: "sparkle.magnifyingglass", prominent: true, action: onReview)
            .accessibilityIdentifier("result-review")
          ActionButton(title: "New Game", action: onNewGame)
            .accessibilityIdentifier("result-new-game")
          ActionButton(title: "View Board", action: onDone)
        }
      }
      .padding(Spacing.xl)
      .frame(maxWidth: 320)
      .background(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous).fill(Palette.surfaceRaised))
      .overlay(RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous).stroke(Palette.border, lineWidth: 0.75))
      .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
  }

  /// A win is a success moment: maybe ask for an App Store rating (spec W8, once per version).
  private func maybeAskForRating() {
    let version = FeedbackCenter.version
    guard result.winner == userColor, !env.isInMemory, env.feedback.reviewPolicy.shouldAsk(version: version, now: Date()) else { return }
    env.feedback.reviewPolicy.asked(version: version)
    env.telemetry.event("app.review_prompt", metadata: ["after": .string("win")])
    requestReview()
  }
}
