import ChessCoachKit
import ChessKit
import SwiftUI

/// End-of-game card shown over the board.
struct ResultCard: View {
  let result: GameResult
  let userColor: Piece.Color
  let opponentName: String
  let onReview: () -> Void
  let onNewGame: () -> Void
  let onDone: () -> Void

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
}
