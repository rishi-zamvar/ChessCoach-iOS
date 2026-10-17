import ChessCoachKit
import SwiftUI

/// Puzzle Rush: 3 minutes, 3 strikes, puzzles get harder as you solve them.
struct PuzzleRushView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env

  static let duration: TimeInterval = 180
  static let bestKey = "rush.best"

  @State private var startedAt = Date()
  @State private var score = 0
  @State private var strikes = 0
  @State private var current: Puzzle?
  @State private var seen: Set<String> = []
  @State private var over = false
  @State private var best = UserDefaults.standard.integer(forKey: PuzzleRushView.bestKey)
  @State private var isNewBest = false

  /// Starts easy and climbs ~40 points per solve.
  private var targetRating: Int { 450 + score * 40 }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let left = max(0, Self.duration - context.date.timeIntervalSince(startedAt))
      VStack(spacing: 0) {
        HStack {
          Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44) }
          Spacer()
          Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .foregroundStyle(left < 20 ? ChessChrome.lowTime : ChessChrome.textPrimary)
          Spacer()
          HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
              Image(systemName: i < strikes ? "xmark.circle.fill" : "circle")
                .foregroundStyle(i < strikes ? ChessChrome.lowTime : ChessChrome.textSecondary)
            }
          }
          .frame(width: 80)
        }
        .foregroundStyle(ChessChrome.textSecondary)
        .padding(.horizontal, Spacing.s)
        .background(ChessChrome.bar)
        Text("Score \(score)")
          .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(ChessChrome.accentGreen)
          .padding(.vertical, Spacing.xs)
          .accessibilityIdentifier("rush-score")
        if over {
          summary
        } else if let current {
          PuzzleView(puzzle: current, rated: false, rush: true) { outcome in
            guard !over else { return }  // a solve landing after time ran out doesn't count
            if outcome.solvedCleanly { score += 1 } else { strikes += 1 }
            if strikes >= 3 { finish() } else { next() }
          }
          .id(current.id)
        } else {
          Spacer()
        }
      }
      .onChange(of: left <= 0) { _, timeUp in if timeUp, !over { finish() } }
    }
    .background(ChessChrome.background.ignoresSafeArea())
    .onAppear {
      startedAt = Date()
      next()
    }
  }

  private var summary: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      Image(systemName: "bolt.fill").font(.system(size: 50)).foregroundStyle(ChessChrome.accentGreen)
      Text("\(score)").font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(ChessChrome.textPrimary)
      Text(isNewBest ? "New best!" : "Best: \(best)")
        .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(ChessChrome.textSecondary)
      Spacer()
      HStack(spacing: Spacing.s) {
        PuzzleButton(title: "Again", systemImage: "arrow.clockwise", prominent: true) { restart() }
        PuzzleButton(title: "Done", systemImage: "checkmark") { dismiss() }
      }
      .padding(Spacing.m)
    }
  }

  private func next() {
    let themes = ["mateIn1", "hangingPiece", "fork", "mateIn2", "pin", "backRankMate", "skewer", "discoveredAttack"]
    let theme = themes[(score + strikes) % themes.count]
    current = (try? training.puzzles?.puzzles(theme: theme, around: targetRating, excluding: seen, limit: 1))??.first
    if let id = current?.id { seen.insert(id) } else { finish() }  // no puzzles left: end the run
  }

  private func finish() {
    guard !over else { return }
    over = true
    isNewBest = score > best
    if score > best {
      best = score
      UserDefaults.standard.set(score, forKey: Self.bestKey)
    }
    env.telemetry.event("training.rush", metadata: ["score": .int(score), "strikes": .int(strikes)])
  }

  private func restart() {
    score = 0
    strikes = 0
    over = false
    isNewBest = false
    startedAt = Date()
    next()
  }
}
