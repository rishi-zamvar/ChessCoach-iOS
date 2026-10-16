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
    case nil: ("Draw", "equal.circle.fill", ChessChrome.textSecondary)
    case userColor: ("You Won!", "trophy.fill", ChessChrome.accentGreen)
    default: ("\(opponentName) Won", "flag.fill", ChessChrome.lowTime)
    }
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.45).ignoresSafeArea()
        .onTapGesture(perform: onDone)
      VStack(spacing: Spacing.l) {
        Image(systemName: outcome.icon)
          .font(.system(size: 40))
          .foregroundStyle(outcome.tint)
        VStack(spacing: Spacing.xs) {
          Text(outcome.title)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(ChessChrome.textPrimary)
            .accessibilityIdentifier("result-title")
          Text("by \(result.termination.displayName.lowercased())")
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(ChessChrome.textSecondary)
        }
        VStack(spacing: Spacing.s) {
          Button(action: onReview) {
            Label("Game Review", systemImage: "sparkle.magnifyingglass")
              .font(.system(size: 17, weight: .bold, design: .rounded))
              .frame(maxWidth: .infinity, minHeight: 50)
              .foregroundStyle(.white)
              .background(RoundedRectangle(cornerRadius: 10).fill(ChessChrome.accentGreen))
          }
          .accessibilityIdentifier("result-review")
          Button(action: onNewGame) {
            Text("New Game")
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .frame(maxWidth: .infinity, minHeight: 46)
              .foregroundStyle(ChessChrome.textPrimary)
              .background(RoundedRectangle(cornerRadius: 10).fill(ChessChrome.card))
          }
          .accessibilityIdentifier("result-new-game")
          Button(action: onDone) {
            Text("View Board")
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .frame(maxWidth: .infinity, minHeight: 46)
              .foregroundStyle(ChessChrome.textPrimary)
              .background(RoundedRectangle(cornerRadius: 10).fill(ChessChrome.card))
          }
        }
      }
      .padding(Spacing.xl)
      .frame(maxWidth: 320)
      .background(RoundedRectangle(cornerRadius: 16).fill(ChessChrome.bar))
      .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }
  }
}
