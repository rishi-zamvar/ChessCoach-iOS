import ChessCoachKit
import SwiftUI

/// Today's plan: each block with its reason, minutes and a start button.
struct PlanCard: View {
  @Environment(TrainingService.self) private var training
  @State private var running: RunningBlock?

  struct RunningBlock: Identifiable {
    let item: PlanItem
    let tasks: [TrainingTask]
    var id: String { item.id }
  }

  var body: some View {
    Card {
      HStack(alignment: .firstTextBaseline) {
        Eyebrow(text: "Daily plan")
        Spacer()
        let left = Int(training.planMinutesLeft.rounded())
        Text(left > 0 ? "~\(left) min left" : "Done for today")
          .font(Typography.caption)
          .foregroundStyle(left > 0 ? Palette.textSecondary : Palette.primaryDeep)
      }
      VStack(spacing: 0) {
        ForEach(Array(training.plan.enumerated()), id: \.element.id) { index, item in
          PlanRow(item: item, done: training.completedToday.contains(item.id)) {
            running = RunningBlock(item: item, tasks: training.tasks(for: item))
          }
          .accessibilityIdentifier("plan-item-\(index)")
          if index < training.plan.count - 1 {
            Rectangle().fill(Palette.border).frame(height: 0.75).padding(.leading, 44)
          }
        }
      }
      .padding(.top, Spacing.s)
      if let next = training.plan.first(where: { !training.completedToday.contains($0.id) }) {
        PrimaryButton(title: "Start: \(next.title)", action: {
          running = RunningBlock(item: next, tasks: training.tasks(for: next))
        }, icon: "play.fill")
        .accessibilityIdentifier("plan-start")
        .padding(.top, Spacing.m)
      }
    }
    .fullScreenCover(item: $running, onDismiss: { training.refresh() }) { block in
      TrainingRunnerView(title: block.item.title, tasks: block.tasks) {
        training.markDone(block.item)
      }
    }
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
          .font(.system(.title3))
          .foregroundStyle(done ? Palette.success : Palette.primaryDeep)
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(item.title).font(Typography.bodyEmph).foregroundStyle(done ? Palette.textMuted : Palette.ink)
              .strikethrough(done, color: Palette.textMuted)
            Spacer()
            Text("\(max(1, Int(item.minutes.rounded()))) min").font(Typography.caption).foregroundStyle(Palette.textMuted)
          }
          Text(item.reason).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.leading)
        }
      }
      .padding(.vertical, Spacing.m)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
