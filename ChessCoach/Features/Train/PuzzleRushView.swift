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
  /// Every miss this run: reviewed on the summary (spec W2).
  @State private var misses: [Miss] = []
  @State private var analyzing: AnalysisRequest?

  struct Miss: Identifiable {
    let id = UUID()
    let puzzle: Puzzle
    /// The position you faced (after the opponent's setup move) and what you played.
    let fen: String
    let played: String
    var playedSAN: String { FactExtractor.sanLine(fen: fen, ucis: [played]).first ?? played }
    var answerSAN: String { FactExtractor.sanLine(fen: fen, ucis: Array(puzzle.moves.dropFirst().prefix(1))).first ?? "" }
    var why: String?
  }

  /// Starts easy and climbs ~40 points per solve.
  private var targetRating: Int { 450 + score * 40 }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let left = max(0, Self.duration - context.date.timeIntervalSince(startedAt))
      VStack(spacing: 0) {
        HStack {
          Button { dismiss() } label: { Image(systemName: "xmark").font(Typography.symbol(16, weight: .semibold)).frame(width: 44, height: 44) }
            .accessibilityLabel("Close")
          FeedbackButton()
          Spacer()
          Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
            .font(.system(.title2, design: .monospaced).weight(.bold))
            .foregroundStyle(left < 20 ? Palette.danger : Palette.textPrimary)
          Spacer()
          HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
              Image(systemName: i < strikes ? "xmark.circle.fill" : "circle")
                .foregroundStyle(i < strikes ? Palette.danger : Palette.textSecondary)
            }
          }
          .frame(width: 80)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, Spacing.s)
        .background(Palette.surfaceRaised)
        Text("Score \(score)")
          .font(.system(.title3).weight(.heavy)).foregroundStyle(Palette.sage)
          .padding(.vertical, Spacing.xs)
          .accessibilityIdentifier("rush-score")
        if over {
          summary
        } else if let current {
          PuzzleView(puzzle: current, rated: false, rush: true) { outcome in
            guard !over else { return }  // a solve landing after time ran out doesn't count
            if outcome.solvedCleanly { score += 1 } else { strikes += 1 }
            if let played = outcome.missed, let setup = current.moves.first, let fen = PuzzleEngine.after(current.fen, setup) {
              misses.append(Miss(puzzle: current, fen: fen, played: played))
            }
            if strikes >= 3 { finish() } else { next() }
          }
          .id(current.id)
        } else {
          Spacer()
        }
      }
      .onChange(of: left <= 0) { _, timeUp in if timeUp, !over { finish() } }
    }
    .background(Palette.surfaceBase.ignoresSafeArea())
    .screen("rush", board: true)
    .onAppear {
      startedAt = Date()
      next()
    }
  }

  private var summary: some View {
    VStack(spacing: Spacing.l) {
      ScrollView {
        VStack(spacing: Spacing.l) {
          Image(systemName: "bolt.fill").font(Typography.symbol(50)).foregroundStyle(Palette.sage)
            .accessibilityHidden(true)
          Text("\(score)").font(Typography.heroNumber).foregroundStyle(Palette.textPrimary)
          Text(isNewBest ? "New best!" : "Best: \(best)")
            .font(Typography.bodyEmph).foregroundStyle(Palette.textSecondary)
          if !misses.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
              Eyebrow(text: "Your misses")
              ForEach(misses) { miss in missRow(miss) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("rush-misses")
          }
        }
        .padding(Spacing.l)
      }
      HStack(spacing: Spacing.s) {
        ActionButton(title: "Again", systemImage: "arrow.clockwise", prominent: true) { restart() }
        ActionButton(title: "Done", systemImage: "checkmark") { dismiss() }
      }
      .padding(Spacing.m)
    }
    .task { await explainMisses() }
    .fullScreenCover(item: $analyzing) { AnalysisBoardView(request: $0) }
  }

  private func missRow(_ miss: Miss) -> some View {
    Card(padding: Spacing.m) {
      HStack(alignment: .top, spacing: Spacing.m) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: Spacing.s) {
            QualityBadge(quality: .mistake)
            Text("You played \(miss.playedSAN) · the answer was \(miss.answerSAN)")
              .font(Typography.callout.weight(.semibold)).foregroundStyle(Palette.textPrimary)
          }
          Text(miss.why ?? "Working out why…").font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
        Spacer(minLength: 0)
        Button {
          env.telemetry.event("analysis.open", metadata: ["from": .string("rush")])
          analyzing = AnalysisRequest(startFEN: miss.fen, moves: [miss.played], flipped: miss.fen.contains(" b "), title: "Analyze miss")
        } label: {
          Image(systemName: "magnifyingglass").font(Typography.body.weight(.semibold)).foregroundStyle(Palette.sage).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Analyze this position")
      }
    }
  }

  private func explainMisses() async {
    guard let engine = PuzzleEngine(env) else { return }
    for i in misses.indices where misses[i].why == nil {
      misses[i].why = await engine.refutation(fen: misses[i].fen, wrong: misses[i].played)?.caption
        ?? "That let the chance slip. Analyze it to see the line."
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
    env.telemetry.event("rush.done", metadata: ["score": .int(score), "strikes": .int(strikes), "misses": .int(misses.count)])
  }

  private func restart() {
    score = 0
    strikes = 0
    misses = []
    over = false
    isNewBest = false
    startedAt = Date()
    next()
  }
}
