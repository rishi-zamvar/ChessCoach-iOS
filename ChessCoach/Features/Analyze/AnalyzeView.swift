import ChessCoachKit
import SwiftUI

/// Saved games, newest first. Tap one to replay it.
struct AnalyzeView: View {
  @Environment(AppEnvironment.self) private var env
  @State private var games: [GameRecord] = []

  var body: some View {
    NavigationStack {
      ZStack {
        BackgroundAtmosphere()
        ScrollView {
          VStack(alignment: .leading, spacing: Spacing.l) {
            Eyebrow(text: "Analyze")
            Text("Your games")
              .font(Typography.display)
              .foregroundStyle(Palette.ink)
              .padding(.bottom, Spacing.s)
            if games.isEmpty {
              Card {
                EmptyState(
                  title: "No games yet",
                  message: "Play a game and it will show up here for review.",
                  systemImage: "checkerboard.rectangle")
              }
            } else {
              ForEach(games) { game in
                NavigationLink(value: game.id) { GameRow(game: game) }
                  .buttonStyle(.plain)
              }
            }
          }
          .padding(.horizontal, Spacing.xl)
          .padding(.vertical, Spacing.xxl)
        }
      }
      .navigationDestination(for: String.self) { id in
        if let game = games.first(where: { $0.id == id }) { GameReplayView(game: game) }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .onAppear { games = (try? env.gameStore.recent(limit: 100)) ?? [] }
  }
}

private struct GameRow: View {
  let game: GameRecord

  var body: some View {
    Card {
      HStack(spacing: Spacing.m) {
        OutcomeBadge(outcome: game.outcome)
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text("vs \(game.opponentName)")
            .font(Typography.heading)
            .foregroundStyle(Palette.ink)
          Text("Played \(game.userColor) · \(game.terminationText) · \(game.timeControlText)")
            .font(Typography.callout)
            .foregroundStyle(Palette.textSecondary)
          Text(game.endedAt.formatted(date: .abbreviated, time: .shortened))
            .font(Typography.caption)
            .foregroundStyle(Palette.textMuted)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.textMuted)
      }
    }
  }
}
