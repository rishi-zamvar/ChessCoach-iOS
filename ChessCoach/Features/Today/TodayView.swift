import ChessCoachKit
import SwiftUI

struct TodayView: View {
  @Environment(AppEnvironment.self) private var env
  @State private var recent: [GameRecord] = []

  var body: some View {
    ZStack {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Eyebrow(text: "Today · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))")
          Text("Today")
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, Spacing.s)

          Card {
            Eyebrow(text: "Daily plan")
            Text("Your daily plan arrives with Training (M3)")
              .font(Typography.body)
              .foregroundStyle(Palette.textMuted)
              .padding(.top, Spacing.s)
          }

          Card {
            Eyebrow(text: "Recent games")
            if recent.isEmpty {
              EmptyState(title: "No games yet", message: "Finished games show up here.", systemImage: "clock")
            } else {
              VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(recent) { game in
                  HStack(spacing: Spacing.m) {
                    OutcomeBadge(outcome: game.outcome)
                    VStack(alignment: .leading, spacing: 2) {
                      Text("vs \(game.opponentName)")
                        .font(Typography.bodyEmph)
                        .foregroundStyle(Palette.ink)
                      Text("\(game.terminationText) · \(game.endedAt.formatted(.relative(presentation: .named)))")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                    }
                  }
                }
              }
              .padding(.top, Spacing.m)
            }
          }

          Card {
            HStack(spacing: Spacing.m) {
              Image(systemName: "play.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.primaryDeep)
              VStack(alignment: .leading, spacing: 2) {
                Text("Play a game")
                  .font(Typography.titleSmall)
                  .foregroundStyle(Palette.ink)
                Text("Head to Play to start")
                  .font(Typography.callout)
                  .foregroundStyle(Palette.textSecondary)
              }
            }
          }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xxl)
      }
    }
    .onAppear { recent = (try? env.gameStore.recent(limit: 3)) ?? [] }
  }
}
