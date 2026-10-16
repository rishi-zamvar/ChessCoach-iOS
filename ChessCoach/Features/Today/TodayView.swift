import ChessCoachKit
import SwiftUI

struct TodayView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis
  @Environment(TrainingService.self) private var training
  @State private var recent: [GameRecord] = []
  @State private var topMistake: MistakePattern?
  @State private var showSettings = false

  var body: some View {
    ZStack {
      BackgroundAtmosphere()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          HStack {
            Eyebrow(text: "Today · \(Date.now.formatted(.dateTime.month(.abbreviated).day()))")
            Spacer()
            Button { showSettings = true } label: {
              Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(Palette.primaryDeep)
            }
            .accessibilityIdentifier("open-settings")
          }
          Text("Today")
            .font(Typography.display)
            .foregroundStyle(Palette.ink)
            .padding(.bottom, Spacing.s)

          PlanCard()

          WeekCard()

          AIStatusCard()

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
    .sheet(isPresented: $showSettings) { SettingsView() }
    .task(id: analysis.revision) {
      training.refresh()
      recent = (try? env.gameStore.recent(limit: 3)) ?? []
      topMistake = analysis.recurringPatterns().first
    }
  }
}

/// Home PC + AI status: connection, key, spend this month.
struct AIStatusCard: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    Card {
      HStack(alignment: .top, spacing: Spacing.m) {
        Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint).frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
          Eyebrow(text: "Coach AI & home PC")
          Text(title).font(Typography.bodyEmph).foregroundStyle(Palette.ink)
          Text(detail).font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        Spacer()
        Button {
          Task { await env.server.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise").foregroundStyle(Palette.primaryDeep)
        }
        .accessibilityIdentifier("ai-refresh")
      }
    }
  }

  private var icon: String {
    switch env.server.status {
    case .online: "desktopcomputer"
    case .checking: "antenna.radiowaves.left.and.right"
    default: env.server.hasKey ? "sparkles" : "wifi.slash"
    }
  }

  private var tint: Color { env.server.hasKey ? Palette.primaryDeep : Palette.textMuted }

  private var title: String {
    switch env.server.status {
    case .online: env.server.hasKey ? "Connected · AI coaching on" : "Connected · waiting for the key"
    case .checking: "Looking for your PC…"
    default: env.server.hasKey ? "AI coaching on (PC offline)" : "Offline coaching"
    }
  }

  private var detail: String {
    let spent = env.aiStore.spentThisMonth()
    if env.server.hasKey {
      return String(format: "$%.2f of $80 used this month", spent)
    }
    return "Everything works offline. AI explanations and the coach bot turn on once your home PC shares the key over Tailscale."
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
