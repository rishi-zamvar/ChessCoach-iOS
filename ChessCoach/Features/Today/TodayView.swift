import ChessCoachKit
import SwiftUI

/// Today: the plan first, then this week, your top mistake, recent games and a way to play.
/// Everything that looks tappable is (spec W1): no static cards.
struct TodayView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis
  @Environment(TrainingService.self) private var training
  @Environment(\.selectTab) private var selectTab
  @State private var recent: [GameRecord] = []
  @State private var topMistake: MistakePattern?
  @State private var showSettings = false
  @State private var retakeRequested = false
  @State private var reviewGame: GameRecord?
  @State private var practice: TrainView.Running?

  var body: some View {
    ZStack {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          HStack {
            Eyebrow(text: "Today · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))")
            Spacer()
            FeedbackButton()
            Button { showSettings = true } label: {
              Image(systemName: "gearshape").font(Typography.body).foregroundStyle(Palette.sage).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("open-settings")
            .accessibilityLabel("Settings")
          }
          Text("Today")
            .font(Typography.display)
            .foregroundStyle(Palette.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, Spacing.s)

          PlanCard()

          WeekCard { startReviews() }

          if let topMistake {
            Button { startPractice(topMistake) } label: {
              Card {
                HStack(alignment: .top) {
                  VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Your top mistake")
                    Text(topMistake.title)
                      .font(Typography.titleSmall)
                      .foregroundStyle(Palette.textPrimary)
                      .padding(.top, Spacing.s)
                    Text("\(topMistake.count) times in your last games. Practise those positions now.")
                      .font(Typography.callout)
                      .foregroundStyle(Palette.textSecondary)
                      .padding(.top, Spacing.xs)
                  }
                  Spacer(minLength: Spacing.s)
                  Image(systemName: "chevron.right").foregroundStyle(Palette.textTertiary)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-top-mistake")
          }

          Card {
            Eyebrow(text: "Recent games")
            if recent.isEmpty {
              EmptyState(title: "No games yet", message: "Finished games show up here.", systemImage: "clock")
            } else {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(recent) { game in
                  Button { reviewGame = game } label: {
                    HStack(spacing: Spacing.m) {
                      OutcomeBadge(outcome: game.outcome)
                      VStack(alignment: .leading, spacing: 2) {
                        Text("vs \(game.opponentName)")
                          .font(Typography.bodyEmph)
                          .foregroundStyle(Palette.textPrimary)
                        Text("\(game.terminationText) · \(game.endedAt.formatted(.relative(presentation: .named)))")
                          .font(Typography.caption)
                          .foregroundStyle(Palette.textSecondary)
                      }
                      Spacer()
                      Text("Review").font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.sage)
                    }
                    .padding(.vertical, Spacing.s)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(.top, Spacing.s)
            }
          }

          Button { selectTab(.play) } label: {
            Card {
              HStack(spacing: Spacing.m) {
                Image(systemName: "play.circle")
                  .font(Typography.symbol(28, weight: .light))
                  .foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Play a game")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Palette.textPrimary)
                  Text("The coach, Maia or Stockfish")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textTertiary)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("today-play")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, 80)
      }
    }
    .screen("today", context: ["plan_done": .bool(training.isPlanDone), "blocks": .int(training.plan.count), "done": .int(training.completedToday.count)])
    .sheet(isPresented: $showSettings, onDismiss: {
      // Present onboarding only after the Settings sheet is fully gone.
      if retakeRequested {
        retakeRequested = false
        training.resetProfile()
      }
    }) {
      SettingsView(onRetake: { retakeRequested = true })
    }
    .fullScreenCover(item: $reviewGame) { ReviewScreen(game: $0) }
    .fullScreenCover(item: $practice, onDismiss: { training.refresh() }) { run in
      TrainingRunnerView(title: run.title, tasks: run.tasks)
    }
    .task(id: analysis.revision) {
      training.refresh()
      recent = (try? env.gameStore.recent(limit: 3)) ?? []
      topMistake = analysis.recurringPatterns().first
    }
  }

  private func startPractice(_ pattern: MistakePattern) {
    env.telemetry.event("today.top_mistake", metadata: ["pattern": .string(pattern.key)])
    practice = TrainView.Running(title: pattern.title, tasks: training.patternTasks(key: pattern.key))
  }

  private func startReviews() {
    let tasks = training.reviewTasks(kind: nil, limit: 10, now: Date())
    env.telemetry.event("today.reviews", metadata: ["due": .int(tasks.count)])
    practice = TrainView.Running(title: "Spaced review", tasks: tasks)
  }
}

/// This week at a glance: games, puzzles, lessons, reviews due (tap to review them).
struct WeekCard: View {
  var onReviews: () -> Void = {}
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
            .font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.rose)
            .accessibilityIdentifier("streak")
        }
      }
      HStack(spacing: Spacing.l) {
        stat("\(games)", "games")
        stat("\(puzzles)", "puzzles")
        stat("\(training.lessonProgress.values.filter(\.passed).count)", "lessons")
        Button(action: onReviews) {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(training.dueReviewCount)").font(Typography.titleSmall).foregroundStyle(Palette.sage)
            Text("to review").font(Typography.caption).foregroundStyle(Palette.sage).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(training.dueReviewCount == 0)
        .accessibilityLabel("\(training.dueReviewCount) reviews due")
        .accessibilityHint("Review them now")
        .accessibilityIdentifier("week-reviews")
      }
      .padding(.top, Spacing.s)
    }
    .task(id: training.revision) {
      let weekAgo = Date().addingTimeInterval(-7 * 86_400)
      games = ((try? env.gameStore.recent(limit: 200)) ?? []).filter { $0.endedAt >= weekAgo }.count
      puzzles = (try? training.store.attemptsCount(since: weekAgo)) ?? 0
      streak = training.streak()
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(Typography.titleSmall).foregroundStyle(Palette.textPrimary)
      Text(label).font(Typography.caption).foregroundStyle(Palette.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
