import ChessCoachKit
import SwiftUI

/// Plays one plan block (or any task list) full-screen, then shows a summary.
struct TrainingRunnerView: View {
  let title: String
  let tasks: [TrainingTask]
  /// Called when the user finishes the whole block (marks the plan item done).
  var onComplete: () -> Void = {}

  @Environment(\.dismiss) private var dismiss
  @Environment(TrainingService.self) private var training
  @State private var index = 0
  @State private var cleanSolves = 0
  @State private var startRating = 0
  @State private var finished = false

  var body: some View {
    VStack(spacing: 0) {
      header
      if tasks.isEmpty {
        Spacer()
        Text("Nothing to do here right now.").foregroundStyle(Palette.textSecondary)
        Spacer()
      } else if finished {
        summary
      } else {
        content(tasks[index])
          .id(tasks[index].id)
          .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
      }
    }
    .background(Palette.surfaceBase.ignoresSafeArea())
    .onAppear { startRating = training.globalRating }
  }

  private var header: some View {
    HStack {
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(Typography.symbol(16, weight: .semibold)).frame(width: 44, height: 44)
      }
      .accessibilityIdentifier("runner-close")
      Spacer()
      VStack(spacing: 2) {
        Text(title).font(.system(.subheadline).weight(.bold)).lineLimit(1)
        if tasks.count > 1 && !finished {
          Text("\(index + 1) of \(tasks.count)").font(.system(.caption))
        }
      }
      Spacer()
      Color.clear.frame(width: 44, height: 44)
    }
    .foregroundStyle(Palette.textSecondary)
    .padding(.horizontal, Spacing.s)
    .background(Palette.surfaceRaised)
    .overlay(alignment: .bottom) {
      GeometryReader { proxy in
        Rectangle().fill(Palette.sage)
          .frame(width: proxy.size.width * CGFloat(finished ? tasks.count : index) / CGFloat(max(1, tasks.count)), height: 3)
          .animation(.easeOut, value: index)
      }
      .frame(height: 3)
    }
  }

  @ViewBuilder
  private func content(_ task: TrainingTask) -> some View {
    switch task {
    case .puzzle(let puzzle):
      PuzzleView(puzzle: puzzle) { advance(clean: $0.solvedCleanly) }
    case .review(let item, let puzzle):
      PuzzleView(puzzle: puzzle, review: item, hasSetupMove: item.kind == .puzzle, insight: training.insight(for: item)) {
        advance(clean: $0.solvedCleanly)
      }
    case .drill(let kind):
      VisionDrillView(kind: kind) { correct, total in
        advance(clean: correct * 10 >= total * 7)
      }
    case .lesson(let lesson):
      LessonView(lesson: lesson) { score, total in
        training.recordLesson(lesson, score: score, of: total)
        advance(clean: score * 10 >= total * 7)
      }
    }
  }

  private func advance(clean: Bool) {
    if clean { cleanSolves += 1 }
    withAnimation(.easeInOut(duration: 0.25)) {
      if index + 1 < tasks.count {
        index += 1
      } else {
        finished = true
        onComplete()
      }
    }
  }

  private var summary: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      Image(systemName: "checkmark.seal.fill").font(Typography.symbol(54)).foregroundStyle(Palette.success)
      Text("Block complete").font(.system(.title).weight(.bold)).foregroundStyle(Palette.textPrimary)
      Text("\(cleanSolves) of \(tasks.count) clean")
        .font(.system(.body).weight(.semibold)).foregroundStyle(Palette.textSecondary)
      let delta = training.globalRating - startRating
      if delta != 0 {
        Text("Puzzle rating \(training.globalRating) (\(delta > 0 ? "+" : "")\(delta))")
          .font(.system(.subheadline).weight(.medium))
          .foregroundStyle(delta > 0 ? Palette.success : Palette.danger)
      }
      Spacer()
      ActionButton(title: "Done", systemImage: "checkmark", prominent: true) { dismiss() }
        .accessibilityIdentifier("runner-done")
        .padding(Spacing.m)
    }
    .frame(maxWidth: .infinity)
  }
}
