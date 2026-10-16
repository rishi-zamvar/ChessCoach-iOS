import ChessCoachKit
import SwiftUI

/// Train hub: puzzle rating, today's plan, skills (themed sets), lessons, and what's coming.
struct TrainView: View {
  @Environment(TrainingService.self) private var training
  @State private var running: Running?
  @State private var showOpenings = false
  @State private var coachGame: GameController?
  @Environment(AppEnvironment.self) private var env

  struct Running: Identifiable {
    let id = UUID()
    let title: String
    let tasks: [TrainingTask]
  }

  var body: some View {
    ZStack {
      BackgroundAtmosphere().ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Eyebrow(text: "Train")
          Text("Train").font(Typography.display).foregroundStyle(Palette.ink)

          ratingCard
          PlanCard()

          SectionHeader(title: "Skills", subtitle: "Six puzzles at your level. Ratings move with every attempt.")
          LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)], spacing: Spacing.m) {
            ForEach(SkillCatalog.suggested(forRating: training.globalRating)) { skill in
              SkillTile(skill: skill, rating: training.skillRatings[skill.id]) {
                start(skill: skill)
              }
              .accessibilityIdentifier("skill-\(skill.id)")
            }
          }

          SectionHeader(title: "Lessons", subtitle: "Learn the idea, then drill it.")
          VStack(spacing: Spacing.s) {
            ForEach(Curriculum.shared.lessons) { lesson in
              LessonRow(lesson: lesson, progress: training.lessonProgress[lesson.id]) {
                running = Running(title: lesson.title, tasks: [.lesson(lesson)])
              }
            }
          }

          SectionHeader(title: "Openings")
          Button { showOpenings = true } label: {
            Card {
              HStack(spacing: Spacing.m) {
                Image(systemName: "book.closed").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.primaryDeep)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Your repertoire").font(Typography.titleSmall).foregroundStyle(Palette.ink)
                  Text("Learn and drill the openings for your style.").font(Typography.callout).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textMuted)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("open-openings")

          SectionHeader(title: "Play Coach")
          Button {
            coachGame = env.makeGame(
              PlayConfig(opponent: .maia(rating: 1100), userColor: ColorChoice.random.resolve(), timeControl: .untimed), coached: true)
          } label: {
            Card {
              HStack(spacing: Spacing.m) {
                Image(systemName: "person.wave.2").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.primaryDeep)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Play with the coach").font(Typography.titleSmall).foregroundStyle(Palette.ink)
                  Text("A real game vs Maia. The coach stops you after mistakes, nudges you about threats, and gives hints.")
                    .font(Typography.callout).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.textMuted)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("play-coach")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, 80)
      }
    }
    .sheet(isPresented: $showOpenings) { OpeningsView() }
    .fullScreenCover(item: $coachGame) { game in
      GameScreen(game: game) { coachGame = nil }
    }
    .fullScreenCover(item: $running, onDismiss: { training.refresh() }) { run in
      TrainingRunnerView(title: run.title, tasks: run.tasks)
    }
  }

  private var ratingCard: some View {
    Card {
      HStack(alignment: .lastTextBaseline) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Eyebrow(text: "Puzzle rating")
          Text("\(training.globalRating)")
            .font(Typography.weightLarge)
            .foregroundStyle(Palette.ink)
            .accessibilityIdentifier("puzzle-rating")
        }
        Spacer()
        VStack(alignment: .trailing, spacing: Spacing.xs) {
          if training.dueReviewCount > 0 {
            Text("\(training.dueReviewCount) review\(training.dueReviewCount == 1 ? "" : "s") due")
              .font(Typography.callout).foregroundStyle(Palette.accentDeep)
          }
          if let style = training.profile?.style {
            Text("\(style.title) · like \(style.model)").font(Typography.caption).foregroundStyle(Palette.textSecondary)
          }
        }
      }
    }
  }

  private func start(skill: Skill) {
    let rating = Int(training.skillRatings[skill.id]?.rating ?? Double(training.globalRating))
    let tasks: [TrainingTask]
    switch skill.source {
    case .drill(let kind): tasks = [.drill(kind)]
    case .puzzles(let themes): tasks = training.puzzleTasks(themes: themes, rating: max(400, rating - 150), count: 6)
    }
    running = Running(title: skill.name, tasks: tasks)
  }
}

private struct SkillTile: View {
  let skill: Skill
  let rating: Glicko2?
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.light(); action() }) {
      VStack(alignment: .leading, spacing: Spacing.s) {
        HStack {
          Image(systemName: skill.systemImage).font(.system(size: 18)).foregroundStyle(Palette.primaryDeep)
          Spacer()
          if let rating, skill.themes.isEmpty == false {
            Text("\(Int(rating.rating))")
              .font(.system(size: 13, weight: .semibold, design: .rounded))
              .foregroundStyle(rating.deviation > 150 ? Palette.textMuted : Palette.ink)
          }
        }
        Text(skill.name).font(Typography.bodyEmph).foregroundStyle(Palette.ink).lineLimit(1)
        Text(skill.summary).font(Typography.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
          .multilineTextAlignment(.leading)
      }
      .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
      .padding(Spacing.m)
      .background(Palette.paper)
      .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).stroke(Palette.border, lineWidth: 0.75))
    }
    .buttonStyle(.plain)
  }
}

private struct LessonRow: View {
  let lesson: Lesson
  let progress: LessonProgress?
  let action: () -> Void

  var body: some View {
    Button(action: { Haptics.light(); action() }) {
      HStack(spacing: Spacing.m) {
        Image(systemName: progress?.passed == true ? "checkmark.circle.fill" : "book")
          .font(.system(size: 18))
          .foregroundStyle(progress?.passed == true ? Palette.success : Palette.primaryDeep)
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(lesson.title).font(Typography.bodyEmph).foregroundStyle(Palette.ink)
          Text(progress.map { "Best \($0.bestScore)/\(lesson.mastery.of)" } ?? "Not started")
            .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMuted)
      }
      .padding(Spacing.m)
      .background(Palette.paper)
      .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).stroke(Palette.border, lineWidth: 0.75))
    }
    .buttonStyle(.plain)
  }
}
