import ChessCoachKit
import ChessKit
import SwiftUI

/// A taught lesson: idea → worked example (narrated, with arrows) → faded example
/// (you finish it) → practice set scored against the mastery bar.
struct LessonView: View {
  let lesson: Lesson
  let onFinished: (_ score: Int, _ total: Int) -> Void

  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue

  enum Stage: Equatable { case idea, worked, faded, practice, result }

  @State private var stage: Stage = .idea
  @State private var workedStep = 0
  @State private var analyzing: AnalysisRequest?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var workedGame = GameSession()
  @State private var fadedDone = false
  @State private var practice: [Puzzle] = []
  @State private var practiceIndex = 0
  @State private var practiceCorrect = 0

  var body: some View {
    Group {
      switch stage {
      case .idea: idea
      case .worked: worked
      case .faded: faded
      case .practice: practiceStage
      case .result: result
      }
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
    .fullScreenCover(item: $analyzing) { AnalysisBoardView(request: $0) }
  }

  private var theme: BoardTheme { BoardTheme.named(themeID) }
  private var pieceSet: PieceSetID { PieceSetID(rawValue: pieceSetRaw) ?? .default }

  // MARK: - Idea

  private var idea: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.m) {
          Text(lesson.title)
            .font(.system(.title, design: .serif).weight(.bold))
            .foregroundStyle(Palette.textPrimary)
          Text(lesson.idea)
            .font(.system(.body))
            .foregroundStyle(Palette.textPrimary.opacity(0.92))
            .lineSpacing(4)
          VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(Array(lesson.keyPoints.enumerated()), id: \.offset) { _, point in
              HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                Text(point).font(.system(.subheadline).weight(.medium)).foregroundStyle(Palette.textPrimary)
              }
            }
          }
          .padding(Spacing.m)
          .background(RoundedRectangle(cornerRadius: Spacing.cornerMedium).fill(Palette.surfaceRaised))
        }
        .padding(Spacing.l)
      }
      ActionButton(title: "See it in action", systemImage: "play.fill", prominent: true) { startWorked() }
        .accessibilityIdentifier("lesson-next")
        .padding(Spacing.m)
    }
  }

  // MARK: - Worked example

  private var worked: some View {
    let ex = lesson.worked
    let narration = workedStep == 0 ? (ex.intro ?? "Watch the moves.") : ex.narration[workedStep - 1]
    return VStack(spacing: 0) {
      coachLine(narration)
      BoardView(
        position: workedGame.position,
        highlights: BoardHighlights.make(session: workedGame, ply: workedGame.history.count, interaction: BoardInteraction()),
        annotations: workedArrows,
        theme: theme, pieceSet: pieceSet,
        flipped: Position(fen: ex.fen)?.sideToMove == .black,
        interactive: false)
      Spacer(minLength: 0)
      HStack(spacing: Spacing.s) {
        StepButton(systemImage: "chevron.left", enabled: workedStep > 0) { unstepWorked() }
          .accessibilityIdentifier("lesson-back")
        ActionButton(title: "", systemImage: "magnifyingglass", label: "Analyze this position") {
          env.telemetry.event("analysis.open", metadata: ["from": .string("lesson")])
          analyzing = AnalysisRequest(
            startFEN: ex.fen, moves: Array(ex.moves.prefix(workedStep)),
            flipped: Position(fen: ex.fen)?.sideToMove == .black, title: "Analyze lesson")
        }
        .frame(width: 56)
        .accessibilityIdentifier("lesson-analyze")
        if workedStep < ex.moves.count {
          ActionButton(title: workedStep == 0 ? "Play" : "Next move", systemImage: "forward.fill", prominent: true) { stepWorked() }
            .accessibilityIdentifier("lesson-step")
        } else {
          ActionButton(title: "Your turn", systemImage: "hand.point.up.left.fill", prominent: true) { stage = .faded }
            .accessibilityIdentifier("lesson-next")
        }
      }
      .padding(Spacing.m)
    }
  }

  private var workedArrows: AnnotationLayer {
    var layer = AnnotationLayer()
    let ex = lesson.worked
    // Arrows for the move about to be played (or just played at the end).
    let index = min(workedStep, ex.arrows.count - 1)
    if index >= 0, index < ex.arrows.count {
      layer.arrows = ex.arrows[index].compactMap { a in
        guard SquareParse.isSquare(a.from), SquareParse.isSquare(a.to) else { return nil }
        return Arrow(from: Square(a.from), to: Square(a.to), color: AnnotationColor(rawValue: a.color) ?? .green)
      }
    }
    return layer
  }

  private func startWorked() {
    workedGame = GameSession(startFEN: lesson.worked.fen)
    workedStep = 0
    stage = .worked
  }

  private func unstepWorked() {
    guard workedStep > 0 else { return }
    workedGame.undo()
    workedStep -= 1
    Haptics.selection()
  }

  private func stepWorked() {
    let ex = lesson.worked
    guard workedStep < ex.moves.count else { return }
    if case .applied(let played) = workedGame.apply(uci: ex.moves[workedStep]) {
      env.sounds.play(SoundEvent.forMove(played, gameOver: workedGame.isOver))
    }
    workedStep += 1
  }

  // MARK: - Faded example

  private var faded: some View {
    let f = lesson.faded
    let puzzle = Puzzle(
      id: "lesson-\(lesson.id)-faded", fen: f.fen, moves: f.solution, rating: lesson.band.first ?? 600, rd: 100,
      popularity: 100, themes: lesson.practice.themes ?? [lesson.skill], primaryTheme: lesson.practice.themes?.first ?? lesson.skill,
      opening: nil)
    return VStack(spacing: 0) {
      coachLine(fadedDone ? f.explanation : "\(f.prompt) Hint if you need it: \(f.hint)")
      PuzzleView(puzzle: puzzle, hasSetupMove: false, rated: false) { _ in
        fadedDone = true
        startPractice()
      }
    }
  }

  // MARK: - Practice

  @ViewBuilder
  private var practiceStage: some View {
    switch lesson.practice.kind {
    case .playout:
      PlayoutView(practice: lesson.practice) { wins, total in
        practiceCorrect = wins
        finishPractice(total: total)
      }
    case .coordinates, .checksCaptures, .safeMove:
      VisionDrillView(kind: drillKind(lesson.practice.kind)) { correct, total in
        practiceCorrect = correct
        practice = []
        finishPractice(total: total)
      }
    default:
      if practiceIndex < practice.count {
        VStack(spacing: 0) {
          Text("Practice \(practiceIndex + 1) of \(practice.count)")
            .font(.system(.footnote).weight(.semibold)).foregroundStyle(Palette.textSecondary)
            .padding(.top, Spacing.xs)
          PuzzleView(puzzle: practice[practiceIndex]) { outcome in
            if outcome.solvedCleanly { practiceCorrect += 1 }
            if practiceIndex + 1 < practice.count { practiceIndex += 1 } else { finishPractice(total: practice.count) }
          }
          .id(practice[practiceIndex].id)
        }
      } else {
        Color.clear.onAppear { finishPractice(total: 0) }
      }
    }
  }

  @State private var practiceTotal = 0

  private func startPractice() {
    let p = lesson.practice
    if p.kind == .puzzles, let themes = p.themes, !themes.isEmpty {
      let low = p.rating?.first ?? 400
      let high = p.rating?.last ?? 1000
      let target = min(high, max(low, training.globalRating - 150))
      let tasks = training.puzzleTasks(themes: themes, rating: target, count: p.count)
      practice = tasks.compactMap { if case .puzzle(let puzzle) = $0 { puzzle } else { nil } }
    }
    practiceIndex = 0
    practiceCorrect = 0
    stage = .practice
  }

  private func finishPractice(total: Int) {
    practiceTotal = total
    stage = .result
  }

  // MARK: - Result

  private var passed: Bool { lesson.isPassed(score: practiceCorrect, total: practiceTotal) }

  private var result: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      Image(systemName: passed ? "star.circle.fill" : "arrow.clockwise.circle.fill")
        .font(Typography.symbol(56)).foregroundStyle(passed ? Palette.success : MoveClass.inaccuracy.color)
      Text(passed ? "Lesson mastered" : "Almost there")
        .font(.system(.title).weight(.bold)).foregroundStyle(Palette.textPrimary)
      if practiceTotal == 0 {
        Text("No practice positions were available — try again later.")
          .font(.system(.subheadline).weight(.medium)).foregroundStyle(Palette.textSecondary)
      } else {
        Text("\(practiceCorrect) of \(practiceTotal) · need \(lesson.mastery.required) of \(lesson.mastery.of)")
          .font(.system(.subheadline).weight(.medium)).foregroundStyle(Palette.textSecondary)
      }
      Text(passed ? "It'll come back in your reviews so it sticks." : "Try again tomorrow — it'll be in your plan.")
        .font(.system(.callout)).foregroundStyle(Palette.textSecondary)
      Spacer()
      HStack(spacing: Spacing.s) {
        if !passed, practiceTotal > 0 {
          ActionButton(title: "Practice again", systemImage: "arrow.counterclockwise") { startPractice() }
            .accessibilityIdentifier("lesson-retry")
        }
        ActionButton(title: "Continue", systemImage: "checkmark", prominent: true) {
          onFinished(practiceCorrect, practiceTotal)
        }
        .accessibilityIdentifier("lesson-finish")
      }
      .padding(Spacing.m)
    }
  }

  // MARK: - Helpers

  private func coachLine(_ text: String) -> some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      Text("♞").font(Typography.symbol(22, design: .serif)).foregroundStyle(Palette.sage)
        .frame(width: 36, height: 36).background(Circle().fill(Palette.surfaceRaised))
      Text(text).font(.system(.subheadline).weight(.medium)).foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Spacing.cornerMedium).fill(Palette.surfaceRaised))
        .accessibilityIdentifier("lesson-narration")
    }
    .padding(Spacing.m)
    .frame(minHeight: 90, alignment: .top)
  }

  private func drillKind(_ kind: Practice.Kind) -> DrillKind {
    switch kind {
    case .checksCaptures: .checksCaptures
    case .safeMove: .safeMove
    default: .coordinates
    }
  }
}

enum SquareParse {
  static func isSquare(_ text: String) -> Bool {
    let c = Array(text)
    return c.count == 2 && ("a"..."h").contains(String(c[0])) && ("1"..."8").contains(String(c[1]))
  }
}
