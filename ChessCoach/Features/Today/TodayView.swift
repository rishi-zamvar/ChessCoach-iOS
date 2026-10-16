import ChessCoachKit
import SwiftUI

struct TodayView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis
  @Environment(TrainingService.self) private var training
  @State private var recent: [GameRecord] = []
  @State private var topMistake: MistakePattern?

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

          PlanCard()

          if let topMistake {
            Card {
              Eyebrow(text: "Your top mistake")
              Text(topMistake.title)
                .font(Typography.titleSmall)
                .foregroundStyle(Palette.ink)
                .padding(.top, Spacing.s)
              Text("\(topMistake.count) times in your last games — today's plan targets it.")
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, Spacing.xs)
            }
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
    .task(id: analysis.revision) {
      training.refresh()
      recent = (try? env.gameStore.recent(limit: 3)) ?? []
      topMistake = analysis.recurringPatterns().first
    }
  }
}
