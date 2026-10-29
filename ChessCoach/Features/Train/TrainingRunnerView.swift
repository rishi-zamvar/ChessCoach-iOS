import ChessCoachKit
import SwiftUI

/// Plays one plan block (or any task list) full-screen, then shows a summary that points forward:
/// "Next: <block>" when there's more to do today, never just a dead-end "Done".
struct TrainingRunnerView: View {
  let title: String
  let tasks: [TrainingTask]
  /// The plan's next block (title, minutes), offered on the summary.
  var next: (title: String, minutes: Double)? = nil
  /// Called once when the block is finished; `true` when it had nothing to do (marked done anyway).
  var onComplete: (_ empty: Bool) -> Void = { _ in }
  /// The user chose "Next" on the summary.
  var onNext: (() -> Void)? = nil
  /// Coach-mode puzzles allowed (not for Quick warm-up, which drills speed).
  var allowCoach = true

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @State private var index = 0
  @State private var cleanSolves = 0
  @State private var startRating = 0
  @State private var finished = false
  @State private var confirmLeave = false

  var body: some View {
    VStack(spacing: 0) {
      header
      if tasks.isEmpty {
        emptyBlock
      } else if finished {
        summary
      } else {
        content(tasks[index])
          .id(tasks[index].id)
          .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
      }
    }
    .background(Palette.surfaceBase.ignoresSafeArea())
    .screen("runner", context: runnerContext, board: true)
    .onAppear {
      startRating = training.globalRating
      // A block with nothing in it (e.g. no reviews left) counts as done, so the plan moves on.
      if tasks.isEmpty { onComplete(true) }
    }
    .confirmationDialog("Leave this block?", isPresented: $confirmLeave, titleVisibility: .visible) {
      Button("Leave", role: .destructive) {
        env.telemetry.event("plan.block_abandon", metadata: ["done": .int(index), "total": .int(tasks.count)])
        dismiss()
      }
      Button("Keep going", role: .cancel) {}
    } message: {
      Text("Your \(index) finished \(index == 1 ? "puzzle is" : "puzzles are") saved. The block stays open in today's plan.")
    }
  }

  /// What feedback from this screen carries: the block, the task, and the puzzle's position.
  private var runnerContext: [String: JSONValue] {
    var c: [String: JSONValue] = ["block": .string(title), "task": .int(index), "of": .int(tasks.count), "finished": .bool(finished)]
    guard tasks.indices.contains(index) else { return c }
    switch tasks[index] {
    case .puzzle(let p), .review(_, let p):
      c["puzzle"] = .string(p.id)
      c["fen"] = .string(p.fen)
      c["theme"] = .string(p.primaryTheme)
    case .drill(let d): c["drill"] = .string(d.rawValue)
    case .lesson(let l): c["lesson"] = .string(l.id)
    }
    return c
  }

  private var header: some View {
    HStack {
      Button {
        if index > 0 && !finished && !tasks.isEmpty { confirmLeave = true } else { dismiss() }
      } label: {
        Image(systemName: "xmark").font(Typography.body.weight(.semibold)).frame(width: 44, height: 44)
      }
      .accessibilityIdentifier("runner-close")
      .accessibilityLabel("Close")
      Spacer()
      VStack(spacing: 2) {
        Text(title).font(Typography.bodyEmph).foregroundStyle(Palette.textPrimary).lineLimit(1)
        if tasks.count > 1 && !finished {
          Text("\(index + 1) of \(tasks.count)").font(Typography.caption)
        }
      }
      Spacer()
      FeedbackButton()
    }
    .foregroundStyle(Palette.textSecondary)
    .padding(.horizontal, Spacing.s)
    .background(Palette.surfaceRaised)
    .overlay(alignment: .bottom) {
      GeometryReader { proxy in
        Rectangle().fill(Palette.sage)
          .frame(width: proxy.size.width * CGFloat(finished ? tasks.count : index) / CGFloat(max(1, tasks.count)), height: 3)
          .animation(reduceMotion ? nil : .easeOut, value: index)
      }
      .frame(height: 3)
    }
  }

  @ViewBuilder
  private func content(_ task: TrainingTask) -> some View {
    switch task {
    case .puzzle(let puzzle) where coach:
      CoachPuzzleView(puzzle: puzzle) { advance(clean: $0.solvedCleanly) }
    case .puzzle(let puzzle):
      PuzzleView(puzzle: puzzle) { advance(clean: $0.solvedCleanly) }
    case .review(let item, let puzzle) where coach && item.kind == .puzzle:
      CoachPuzzleView(puzzle: puzzle, review: item, hasSetupMove: true) { advance(clean: $0.solvedCleanly) }
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

  /// Coach mode is on, allowed for this block, and the engine is there to grade moves.
  private var coach: Bool { allowCoach && PuzzleMode.current == .coach && env.engineHost != nil }

  private func advance(clean: Bool) {
    if clean { cleanSolves += 1 }
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
      if index + 1 < tasks.count {
        index += 1
      } else {
        finished = true
        onComplete(false)
      }
    }
  }

  private var emptyBlock: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      EmptyState(title: "Nothing due here", message: "You're up to date on this one, so it's ticked off.", systemImage: "checkmark.circle")
      forwardButtons
    }
    .accessibilityIdentifier("runner-empty")
  }

  private var summary: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      Image(systemName: "checkmark.seal.fill").font(Typography.symbol(54)).foregroundStyle(Palette.success)
        .accessibilityHidden(true)
      Text("Block complete").font(Typography.title).foregroundStyle(Palette.textPrimary)
      Text("\(cleanSolves) of \(tasks.count) clean")
        .font(Typography.bodyEmph).foregroundStyle(Palette.textSecondary)
      let delta = training.globalRating - startRating
      if delta != 0 {
        Text("Puzzle rating \(training.globalRating) (\(delta > 0 ? "+" : "")\(delta))")
          .font(Typography.callout.weight(.medium))
          .foregroundStyle(delta > 0 ? Palette.success : Palette.danger)
      }
      forwardButtons
    }
    .frame(maxWidth: .infinity)
  }

  /// "Next: <block>" first when the plan has more today; otherwise back to Today.
  @ViewBuilder private var forwardButtons: some View {
    VStack(spacing: Spacing.s) {
      Spacer()
      if let next, let onNext {
        PrimaryButton(title: "Next: \(next.title) (\(max(1, Int(next.minutes.rounded()))) min)", action: onNext, icon: "arrow.right")
          .accessibilityIdentifier("runner-next")
        SecondaryButton(title: "Back to Today") { dismiss() }
          .accessibilityIdentifier("runner-done")
      } else {
        PrimaryButton(title: "Done", action: { dismiss() }, icon: "checkmark")
          .accessibilityIdentifier("runner-done")
      }
    }
    .padding(Spacing.l)
  }
}
