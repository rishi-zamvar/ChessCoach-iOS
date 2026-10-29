import ChessCoachKit
import StoreKit
import SwiftUI

/// Today's plan: each block with its reason, minutes and a start button. When every block is done
/// it becomes the completion card (summary + optional next steps), so Today is never a dead end.
struct PlanCard: View {
  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @Environment(\.requestReview) private var requestReview
  @State private var running: RunningBlock?
  /// A block chosen from the runner's "Next" button, started once the runner has closed.
  @State private var queued: PlanItem?
  @State private var coachGame: GameController?
  @State private var reviewGame: GameRecord?

  struct RunningBlock: Identifiable {
    let id = UUID()
    let item: PlanItem?
    let title: String
    let tasks: [TrainingTask]
  }

  var body: some View {
    Group {
      if training.isPlanDone {
        completion
      } else {
        plan
      }
    }
    .fullScreenCover(item: $running, onDismiss: {
      training.refresh()
      if let next = queued {
        queued = nil
        start(next)
      }
    }) { block in
      let next = block.item.flatMap { training.nextBlock(after: $0) }
      TrainingRunnerView(
        title: block.title, tasks: block.tasks, next: next.map { ($0.title, $0.minutes) },
        onComplete: { empty in if let item = block.item { training.markDone(item, empty: empty) } },
        onNext: { queued = next; running = nil },
        allowCoach: block.item.map { if case .speed = $0.kind { false } else { true } } ?? true)
    }
    .fullScreenCover(item: $coachGame) { game in GameScreen(game: game) { coachGame = nil } }
    .fullScreenCover(item: $reviewGame) { ReviewScreen(game: $0) }
  }

  // MARK: - Plan

  private var plan: some View {
    Card {
      HStack(alignment: .firstTextBaseline) {
        Eyebrow(text: "Daily plan")
        Spacer()
        Text("About \(max(1, Int(training.planMinutesLeft.rounded()))) min left")
          .font(Typography.caption)
          .foregroundStyle(Palette.textSecondary)
      }
      VStack(spacing: 0) {
        ForEach(Array(training.plan.enumerated()), id: \.element.id) { index, item in
          PlanRow(item: item, done: training.completedToday.contains(item.id)) { start(item) }
            .accessibilityIdentifier("plan-item-\(index)")
          if index < training.plan.count - 1 {
            Rectangle().fill(Palette.divider).frame(height: 0.75).padding(.leading, 44)
          }
        }
      }
      .padding(.top, Spacing.s)
      if let next = training.nextBlock(after: nil) {
        PrimaryButton(title: "Start: \(next.title)", action: { start(next) }, icon: "play.fill")
          .accessibilityIdentifier("plan-start")
          .padding(.top, Spacing.m)
      }
    }
  }

  private func start(_ item: PlanItem) {
    env.telemetry.event("plan.block_start", metadata: ["kind": .string(item.kindName)])
    running = RunningBlock(item: item, title: item.title, tasks: training.tasks(for: item))
  }

  // MARK: - Done for today

  private var completion: some View {
    Card {
      HStack(alignment: .firstTextBaseline) {
        Eyebrow(text: "Daily plan")
        Spacer()
        Label("Done", systemImage: "checkmark.circle.fill")
          .font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.success)
      }
      Text("Plan done. Nice work.")
        .font(Typography.title).foregroundStyle(Palette.textPrimary)
        .padding(.top, Spacing.s)
        .accessibilityIdentifier("plan-complete")
      Text(summary)
        .font(Typography.callout).foregroundStyle(Palette.textSecondary)
        .padding(.top, Spacing.xs)

      Eyebrow(text: "Want more?").padding(.top, Spacing.l)
      VStack(spacing: 0) {
        if let bonus = training.bonusTasks(), !bonus.tasks.isEmpty {
          cta(bonus.title, "Five more puzzles on today's top skill.", "target", id: "bonus") {
            running = RunningBlock(item: nil, title: bonus.title, tasks: bonus.tasks)
          }
          divider
        }
        if let last = (try? env.gameStore.recent(limit: 1))?.first {
          cta("Review your last game", "vs \(last.opponentName) · see where it turned.", "sparkle.magnifyingglass", id: "review") {
            reviewGame = last
          }
          divider
        }
        cta("Play the coach", "A game that trains \(env.coachFocus.title.lowercased()).", "person.wave.2", id: "coach") {
          coachGame = env.makeGame(PlayConfig(opponent: .teaching, userColor: ColorChoice.random.resolve(), timeControl: .untimed))
        }
      }
      .padding(.top, Spacing.xs)

      Text("Tomorrow: a fresh plan\(tomorrowFocus).")
        .font(Typography.caption).foregroundStyle(Palette.textTertiary)
        .padding(.top, Spacing.m)
    }
    .onAppear {
      // A finished plan is a success moment: maybe ask for an App Store rating (once per version).
      let version = FeedbackCenter.version
      guard env.feedback.reviewPolicy.shouldAsk(version: version, now: Date()), !env.isInMemory else { return }
      env.feedback.reviewPolicy.asked(version: version)
      env.telemetry.event("app.review_prompt")
      requestReview()
    }
  }

  private var summary: String {
    let puzzles = training.puzzlesToday()
    let streak = training.streak()
    var parts = ["\(training.plan.count) blocks", "\(puzzles) puzzle\(puzzles == 1 ? "" : "s")"]
    if streak > 0 { parts.append("\(streak)-day streak") }
    return parts.joined(separator: " · ")
  }

  private var tomorrowFocus: String {
    training.topSkillID.flatMap(SkillCatalog.skill).map { " built around \($0.name.lowercased())" } ?? ""
  }

  private var divider: some View {
    Rectangle().fill(Palette.divider).frame(height: 0.75).padding(.leading, 44)
  }

  private func cta(_ title: String, _ detail: String, _ icon: String, id: String, _ action: @escaping () -> Void) -> some View {
    Button {
      env.telemetry.event("plan.cta", metadata: ["which": .string(id)])
      action()
    } label: {
      HStack(spacing: Spacing.m) {
        Image(systemName: icon).font(Typography.body).foregroundStyle(Palette.sage).frame(width: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(Typography.bodyEmph).foregroundStyle(Palette.textPrimary)
          Text(detail).font(Typography.caption).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary)
      }
      .padding(.vertical, Spacing.m)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("plan-cta-\(id)")
  }
}

private struct PlanRow: View {
  let item: PlanItem
  let done: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: Spacing.m) {
        Image(systemName: done ? "checkmark.circle.fill" : icon)
          .font(.title3)
          .foregroundStyle(done ? Palette.success : Palette.sage)
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(item.title).font(Typography.bodyEmph).foregroundStyle(done ? Palette.textTertiary : Palette.textPrimary)
              .strikethrough(done, color: Palette.textTertiary)
            Spacer()
            Text("\(max(1, Int(item.minutes.rounded()))) min").font(Typography.caption).foregroundStyle(Palette.textTertiary)
          }
          Text(item.reason).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.leading)
        }
      }
      .padding(.vertical, Spacing.m)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(item.title), \(done ? "done" : "\(max(1, Int(item.minutes.rounded()))) minutes"). \(item.reason)")
    .accessibilityHint(done ? "Do it again" : "Start this block")
  }

  private var icon: String {
    switch item.kind {
    case .drill: "square.grid.3x3"
    case .speed: "bolt"
    case .reviews: "arrow.triangle.2.circlepath"
    case .lesson: "book"
    case .themed: "target"
    case .mixed: "shuffle"
    case .ownMistakes: "person.crop.circle.badge.exclamationmark"
    }
  }
}
