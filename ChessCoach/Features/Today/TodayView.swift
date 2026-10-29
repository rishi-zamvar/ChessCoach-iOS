import ChessCoachKit
import SwiftUI

struct TodayView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis
  @Environment(TrainingService.self) private var training
  @State private var recent: [GameRecord] = []
  @State private var topMistake: MistakePattern?
  @State private var showSettings = false
  @State private var retakeRequested = false

  var body: some View {
    ZStack {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          HStack {
            Eyebrow(text: "Today · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))")
            Spacer()
            Button { showSettings = true } label: {
              Image(systemName: "gearshape").font(Typography.symbol(18)).foregroundStyle(Palette.primaryDeep)
            }
            .accessibilityIdentifier("open-settings")
          }
          Text("Today")
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, Spacing.s)

          PlanCard()

          WeekCard()

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
                .font(.system(.title).weight(.light))
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
    .sheet(isPresented: $showSettings, onDismiss: {
      // Present onboarding only after the Settings sheet is fully gone.
      if retakeRequested {
        retakeRequested = false
        training.resetProfile()
      }
    }) {
      SettingsView(onRetake: { retakeRequested = true })
    }
    .task(id: analysis.revision) {
      training.refresh()
      recent = (try? env.gameStore.recent(limit: 3)) ?? []
      topMistake = analysis.recurringPatterns().first
    }
  }
}

/// This week at a glance: games, puzzles, lessons, reviews due.
struct WeekCard: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(TrainingService.self) private var training
  @State private var games = 0
  @State private var puzzles = 0
  @State private var streak = 0

  var body: some View {
    Card {
      HStack {
        Eyebrow(text: "This week")
        Spacer()
        if streak > 0 {
          Label("\(streak)-day streak", systemImage: "flame.fill")
            .font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.accentDeep)
            .accessibilityIdentifier("streak")
        }
      }
      HStack(spacing: Spacing.l) {
        stat("\(games)", "games")
        stat("\(puzzles)", "puzzles")
        stat("\(training.lessonProgress.values.filter(\.passed).count)", "lessons")
        stat("\(training.dueReviewCount)", "reviews due")
      }
      .padding(.top, Spacing.s)
    }
    .task(id: training.revision) {
      let weekAgo = Date().addingTimeInterval(-7 * 86_400)
      games = ((try? env.gameStore.recent(limit: 200)) ?? []).filter { $0.endedAt >= weekAgo }.count
      puzzles = (try? training.store.attemptsCount(since: weekAgo)) ?? 0
      streak = (try? training.store.streak(now: Date())) ?? 0
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(Typography.titleSmall).foregroundStyle(Palette.ink)
      Text(label).font(Typography.caption).foregroundStyle(Palette.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
