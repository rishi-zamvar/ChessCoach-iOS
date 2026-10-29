import ChessCoachKit
import ChessKit
import SwiftUI

/// Outcome of one puzzle, reported to the runner.
struct PuzzleResult: Equatable {
  var solvedCleanly: Bool
  var ratingChange: TrainingService.RatingChange?
  /// Puzzle Rush: the move you played instead (reviewed at the end).
  var missed: String? = nil
}

/// One puzzle in chess.com's puzzle style: prompt bar, board, feedback, hint/next.
struct PuzzleView: View {
  let puzzle: Puzzle
  /// Nil for normal puzzles; set when this is a spaced-repetition review.
  var review: ReviewItem? = nil
  var hasSetupMove = true
  /// For a position from your own game: why your move was a mistake (shown once solved or revealed).
  var insight: MoveInsight? = nil
  /// false for placement: no rating or review updates.
  var rated = true
  /// Puzzle Rush: no hints; a solve or a wrong move ends the puzzle immediately.
  var rush = false
  let onFinished: (PuzzleResult) -> Void

  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue
  @AppStorage(BoardSettings.paceKey) private var paceRaw = ReplyPace.normal.rawValue

  @State private var session: PuzzleSession?
  @State private var interaction = BoardInteraction()
  @State private var feedback: Feedback = .prompt
  @State private var annotations = AnnotationLayer()
  @State private var hintText: String?
  @State private var started = Date()
  @State private var change: TrainingService.RatingChange?
  @State private var recorded = false
  @State private var ready = false
  /// Replaying a finished puzzle for practice: never re-rated, outcome stays the first attempt's.
  @State private var isRetry = false
  @State private var firstOutcome: PuzzleResult?
  /// The ply shown on the board; below the latest while stepping back or pausing before a reply.
  @State private var viewPly = 0
  /// The full solution line once revealed, stepped through with ▶.
  @State private var solutionGame: GameSession?
  /// Waiting for a tap (or the pace delay) before showing the opponent's reply.
  @State private var awaitingReply = false
  @State private var finishing = false
  /// Your wrong move and the engine's punishing reply, shown before the board rewinds (spec W2).
  @State private var refutationGame: GameSession?
  /// Asking the engine about a wrong move (the board waits).
  @State private var checking = false
  @State private var analyzing: AnalysisRequest?
  @AppStorage(BoardSettings.coordinatesKey) private var showCoordinates = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  enum Feedback: Equatable {
    case prompt, correct, wrong(String), solved, revealed
    /// Why the wrong move fails (engine reply + facts).
    case refuted(String)
    /// A different move that also wins (spec W5).
    case alsoWins(String)
  }

  private var isDone: Bool {
    switch feedback {
    case .solved, .revealed, .alsoWins: true
    default: false
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      promptBar
      ZStack {
        if let session {
          BoardView(
            position: Position(fen: shownGame.fen(atPly: viewPly)) ?? session.game.position,
            highlights: highlights(session),
            // Hint and solution arrows belong to the live position (or the refutation being shown).
            annotations: atLatest || refutationGame != nil ? annotations : AnnotationLayer(),
            theme: BoardTheme.named(themeID),
            pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
            flipped: session.userColor == .black,
            showCoordinates: showCoordinates,
            interactive: ready && atLatest && solutionGame == nil && refutationGame == nil && !checking && !isDone,
            onTap: tap,
            onDragBegan: { square in
              guard let s = self.session else { return false }
              return interaction.dragBegan(at: square, session: s.game, userColor: s.userColor)
            },
            onDragEnded: { square in
              guard let s = self.session else { return }
              if case .move(let from, let to) = interaction.dragEnded(at: square, session: s.game, userColor: s.userColor) {
                submit(from: from, to: to)
              }
            },
            onDragCancelled: { interaction.dragCancelled() },
            onArrow: { annotations.toggleUserArrow(from: $0, to: $1) }
          )
          // While browsing back (or waiting on a reply) the board is a big "next" button.
          if !rush, viewPly < shownGame.history.count {
            Color.clear.contentShape(Rectangle())
              .onTapGesture { step(1) }
              .accessibilityIdentifier("board-continue")
          }
        } else {
          Color.clear.aspectRatio(1, contentMode: .fit)
        }
      }
      feedbackBar
      if !rush { moveCaption }
      if let insight, feedback == .solved || feedback == .revealed {
        InsightCard(insight: insight)
      }
      Spacer(minLength: 0)
      if !rush { controls }
    }
    .task(id: puzzle.id) { await start() }
    .fullScreenCover(item: $analyzing) { AnalysisBoardView(request: $0) }
  }

  // MARK: - Pieces

  private var promptBar: some View {
    HStack(spacing: Spacing.s) {
      let color = session?.userColor ?? .white
      RoundedRectangle(cornerRadius: 3)
        .fill(color == .white ? Color.white : Color.black)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Palette.textSecondary, lineWidth: 1))
        .frame(width: 18, height: 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(review == nil ? "\(color == .white ? "White" : "Black") to move" : "Review: \(color == .white ? "White" : "Black") to move")
          .font(.system(.body).weight(.bold))
          .foregroundStyle(Palette.textPrimary)
        Text(subtitle)
          .font(.system(.footnote).weight(.medium))
          .foregroundStyle(Palette.textSecondary)
      }
      Spacer()
      if color == .black {
        // The board is flipped: say so (spec W6).
        Text("You play Black")
          .font(Typography.caption.weight(.semibold))
          .foregroundStyle(Palette.actionLabel)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(Capsule().fill(Palette.action))
          .accessibilityIdentifier("you-play-black")
      }
      if review == nil {
        Text("\(puzzle.rating)")
          .font(.system(.callout).weight(.semibold))
          .foregroundStyle(Palette.textSecondary)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(Capsule().fill(Palette.surfaceRaised))
      }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
  }

  private var subtitle: String {
    if let hintText { return hintText }
    if puzzle.themes.contains(where: { $0.hasPrefix("mateIn") }) {
      return PuzzleThemes.displayName(puzzle.themes.first { $0.hasPrefix("mateIn") }!)
    }
    return review?.kind == .mistake ? "Find the move you missed in your game" : "Find the best move"
  }

  @ViewBuilder
  private var feedbackBar: some View {
    let (icon, text, color): (String, String, Color) = {
      switch feedback {
      case .prompt: return ("", "", .clear)
      case .correct:
        let tap = awaitingReply && paceRaw == ReplyPace.step.rawValue
        return ("checkmark.circle.fill", tap ? "Best move! Tap the board for the reply." : "Best move! Keep going…", Palette.success)
      case .wrong(let san): return ("xmark.circle.fill", checking ? "\(san) isn't it. Here's why…" : "\(san) isn't it. Try again.", Palette.danger)
      case .refuted(let why): return ("xmark.circle.fill", refutationGame == nil ? "\(why) Try again." : why, Palette.danger)
      case .alsoWins(let note): return ("checkmark.seal.fill", note, Palette.success)
      case .solved:
        let delta = isRetry ? "" : change.map { $0.delta >= 0 ? " +\($0.delta)" : " \($0.delta)" } ?? ""
        return ("checkmark.seal.fill", "Solved!\(delta)", Palette.success)
      case .revealed:
        let done = viewPly >= shownGame.history.count
        return ("eye.fill", done ? "That's the full solution." : "Solution: tap ▶ to step through it.", MoveClass.inaccuracy.color)
      }
    }()
    HStack(spacing: Spacing.s) {
      if !icon.isEmpty { Image(systemName: icon).font(Typography.symbol(20)) }
      Text(text).font(Typography.bodyEmph)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("puzzle-feedback")
      Spacer()
    }
    .foregroundStyle(color)
    .padding(.horizontal, Spacing.l)
    .frame(minHeight: 48)
    .animation(.easeOut(duration: 0.2), value: feedback)
  }

  /// What the move on the board does, plus ◀ ▶ to step through the line.
  private var moveCaption: some View {
    HStack(spacing: Spacing.s) {
      StepButton(systemImage: "chevron.left", enabled: viewPly > firstPly) { step(-1) }
        .accessibilityIdentifier("step-back")
      Group {
        if let note = captionNote {
          MoveNote(who: note.who, isYou: note.isYou, san: note.san, text: note.text, compact: true)
        } else {
          Color.clear.frame(height: 1)
        }
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("move-caption")
      .accessibilityLabel(caption)
      StepButton(systemImage: "chevron.right", enabled: viewPly < shownGame.history.count) { step(1) }
        .accessibilityIdentifier("step-forward")
    }
    .padding(.horizontal, Spacing.m)
    .frame(minHeight: 52)
  }

  @ViewBuilder
  private var controls: some View {
    HStack(spacing: Spacing.s) {
      if isDone {
        ActionButton(title: "Retry", systemImage: "arrow.counterclockwise") { Task { await start(retry: true) } }
          .accessibilityIdentifier("puzzle-retry")
        ActionButton(title: "Analyze", systemImage: "magnifyingglass") { openAnalysis() }
          .accessibilityIdentifier("puzzle-analyze")
        ActionButton(title: "Next", systemImage: "arrow.right", prominent: true) { finish() }
          .disabled(finishing)
          .accessibilityIdentifier("puzzle-next")
      } else {
        ActionButton(title: "Hint", systemImage: "lightbulb") { hint() }
          .accessibilityIdentifier("puzzle-hint")
        if showSolutionButton {
          ActionButton(title: "Solution", systemImage: "eye") { reveal() }
            .accessibilityIdentifier("puzzle-solution")
        }
      }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .background(Palette.surfaceRaised)
  }

  private var showSolutionButton: Bool {
    switch feedback {
    case .wrong, .refuted: return true
    default: return (session?.hintsUsed ?? 0) >= 3
    }
  }

  // MARK: - Move cursor

  /// The line on the board: the solution once revealed, otherwise the live puzzle.
  private var shownGame: GameSession { refutationGame ?? solutionGame ?? session?.game ?? GameSession() }
  private var atLatest: Bool { viewPly == (session?.game.history.count ?? 0) }
  /// Never step back past the opponent's setup move — that's where the puzzle starts.
  private var firstPly: Int { hasSetupMove ? min(1, shownGame.history.count) : 0 }

  private var caption: String {
    let history = shownGame.history
    guard viewPly > 0, viewPly <= history.count else {
      return ""
    }
    let played = history[viewPly - 1]
    let who = session.map { played.color == $0.userColor } == true ? "You" : (played.color == .white ? "White" : "Black")
    let why = Explainer.reason(fen: shownGame.fen(atPly: viewPly - 1), uci: played.uci) ?? played.san
    return "\(who): \(why)"
  }

  private var captionNote: (who: String, isYou: Bool, san: String, text: String)? {
    let history = shownGame.history
    guard viewPly > 0, viewPly <= history.count, let s = session else { return nil }
    let played = history[viewPly - 1]
    let isYou = played.color == s.userColor
    let why = Explainer.reason(fen: shownGame.fen(atPly: viewPly - 1), uci: played.uci) ?? played.san
    return (isYou ? "You" : (played.color == .white ? "White" : "Black"), isYou, played.san, why)
  }

  private func step(_ delta: Int) {
    let target = min(max(viewPly + delta, firstPly), shownGame.history.count)
    guard target != viewPly else { return }
    Haptics.selection()
    viewPly = target
    if target > 0 { playSound(shownGame.history[target - 1]) }
    if awaitingReply, target == shownGame.history.count { awaitingReply = false }
  }

  // MARK: - Flow

  private func start(retry: Bool = false) async {
    isRetry = retry
    session = PuzzleSession(puzzle: puzzle, hasSetupMove: hasSetupMove)
    ready = !hasSetupMove
    feedback = .prompt
    hintText = nil
    annotations = AnnotationLayer()
    interaction.reset()
    solutionGame = nil
    refutationGame = nil
    checking = false
    awaitingReply = false
    finishing = false
    viewPly = 0
    if !retry {
      change = nil
      recorded = false
      firstOutcome = nil
    }
    if hasSetupMove {
      try? await Task.sleep(for: .milliseconds(450))
      // Mutate the live session (a hint tapped during the delay must not be lost).
      if var s = session, s.playSetup() != nil {
        session = s
        viewPly = s.game.history.count
        if let last = s.game.lastMove { playSound(last) }
      }
      ready = true
    }
    started = Date()
  }

  private func tap(_ square: Square) {
    guard let s = session else { return }
    if case .move(let from, let to) = interaction.tap(square, session: s.game, userColor: s.userColor) {
      submit(from: from, to: to)
    }
  }

  private func submit(from: Square, to: Square) {
    guard var s = session else { return }
    let before = s.game
    let result = s.submit(from: from, to: to)
    switch result {
    case .ignored:
      return
    case .wrong where rush:
      env.sounds.play(.illegal)
      session = s
      onFinished(PuzzleResult(solvedCleanly: false, ratingChange: nil, missed: s.wrongMoves.last))
    case .wrong:
      var trial = before
      guard case .applied(let played) = trial.apply(from: from, to: to, promotion: trial.isPromotion(from: from, to: to) ? .queen : nil)
      else { return }
      feedback = .wrong(played.san)
      Haptics.warning()
      session = s
      annotations = AnnotationLayer()
      let fen = before.position.fen
      let expected = s.expectedMove
      checking = true
      Task { await explainWrong(fen: fen, played: played, after: trial, expected: expected) }
    case .correct:
      session = s
      feedback = .correct
      hintText = nil
      annotations = AnnotationLayer()
      Haptics.light()
      showReply(s)
    case .solved:
      session = s
      viewPly = s.game.history.count
      feedback = .solved
      Haptics.success()
      annotations = AnnotationLayer()
      env.sounds.play(.gameEnd)
      record(s)
      if rush {
        Task {
          try? await Task.sleep(for: .milliseconds(350))
          onFinished(PuzzleResult(solvedCleanly: true, ratingChange: nil))
        }
      }
    }
  }

  /// A wrong move: first ask whether it still wins (then it counts), otherwise play the engine's
  /// punishing reply on the board with a red arrow and one plain sentence, then rewind (spec W2, W5).
  private func explainWrong(fen: String, played: PlayedMove, after: GameSession, expected: String?) async {
    defer { checking = false }
    guard let engine = PuzzleEngine(env) else { return }
    if let expected, await engine.alsoWins(fen: fen, uci: played.uci, solution: expected), var s = session, s.acceptAlternative(uci: played.uci) {
      session = s
      viewPly = s.game.history.count
      let intended = FactExtractor.sanLine(fen: fen, ucis: [expected]).first ?? expected
      feedback = .alsoWins("Good move, that wins too. The puzzle's move was \(intended).")
      env.telemetry.event("puzzle.wrong_move", metadata: ["reason_kind": .string("also_wins")])
      Haptics.success()
      playSound(played)
      record(s)
      return
    }
    guard let refutation = await engine.refutation(fen: fen, wrong: played.uci), session?.isSolved == false else { return }
    var line = after
    guard case .applied(let reply) = line.apply(uci: refutation.reply) else { return }
    env.telemetry.event("puzzle.wrong_move", metadata: ["reason_kind": .string(refutation.caption.contains("#") ? "mate" : "material")])
    refutationGame = line
    viewPly = line.history.count - 1
    playSound(played)
    try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 600))
    viewPly = line.history.count
    playSound(reply)
    annotations = AnnotationLayer()
    annotations.arrows = [Arrow(from: reply.move.start, to: reply.move.end, color: .red)]
    feedback = .refuted(refutation.caption)
    try? await Task.sleep(for: .seconds(2.4))
    rewindRefutation()
  }

  /// Back to the puzzle position after showing why a move fails.
  private func rewindRefutation() {
    guard refutationGame != nil else { return }
    refutationGame = nil
    annotations = AnnotationLayer()
    viewPly = session?.game.history.count ?? 0
  }

  private func openAnalysis() {
    let game = shownGame
    let start = game.fen(atPly: firstPly)
    let moves = game.history.dropFirst(firstPly).map(\.uci)
    env.telemetry.event("analysis.open", metadata: ["from": .string(rush ? "rush" : "puzzle")])
    analyzing = AnalysisRequest(startFEN: start, moves: Array(moves), flipped: session?.userColor == .black, title: "Analyze puzzle")
  }

  /// Shows your move, then the opponent's reply after the chosen pace (or your tap).
  private func showReply(_ s: PuzzleSession) {
    let latest = s.game.history.count
    viewPly = latest - 1
    if let mine = s.game.history.dropLast().last { playSound(mine) }
    let pace = rush ? .instant : (ReplyPace(rawValue: paceRaw) ?? .normal)
    awaitingReply = true
    guard let delay = pace.delay else { return }
    Task {
      try? await Task.sleep(for: delay)
      // Only advance if nothing moved the cursor meanwhile.
      guard awaitingReply, viewPly == latest - 1, session?.game.history.count == latest else { return }
      step(1)
    }
  }

  private func hint() {
    guard ready, var s = session, let h = s.nextHint() else { return }
    session = s
    switch h {
    case .theme(let name):
      hintText = name.isEmpty ? "Hint: list every check, capture and threat first." : "Hint: look for a \(name.lowercased())."
    case .piece(let square):
      hintText = "Hint: move the highlighted piece."
      annotations.circles = [square: .blue]
    case .move(let from, let to):
      hintText = "The move is shown."
      annotations.circles = [:]
      annotations.arrows = [Arrow(from: from, to: to, color: .green)]
    }
  }

  private func reveal() {
    rewindRefutation()
    guard let s = session, let expected = s.expectedMove.flatMap(UCIMove.init) else { return }
    var line = s.game
    for uci in s.puzzle.moves.dropFirst(s.index) { line.apply(uci: uci) }
    solutionGame = line
    viewPly = s.game.history.count
    awaitingReply = false
    annotations = AnnotationLayer()
    annotations.arrows = [Arrow(from: expected.from, to: expected.to, color: .green)]
    feedback = .revealed
    record(s)
  }

  private func record(_ s: PuzzleSession) {
    guard !recorded else { return }
    recorded = true
    firstOutcome = PuzzleResult(solvedCleanly: s.isSolved && !s.failedFirstTry && s.hintsUsed == 0, ratingChange: nil)
    guard rated else { return }
    let seconds = Date().timeIntervalSince(started)
    if let review {
      training.record(review: review, session: s, seconds: seconds)
    } else {
      change = training.record(puzzle: s, seconds: seconds)
    }
  }

  private func finish() {
    guard !finishing else { return }
    finishing = true
    let clean = firstOutcome?.solvedCleanly ?? session.map { $0.isSolved && !$0.failedFirstTry && $0.hintsUsed == 0 } ?? false
    onFinished(PuzzleResult(solvedCleanly: clean, ratingChange: change))
  }

  private func playSound(_ played: PlayedMove) {
    env.sounds.play(SoundEvent.forMove(played, gameOver: false))
  }

  private func highlights(_ s: PuzzleSession) -> BoardHighlights {
    var h = BoardHighlights.make(session: shownGame, ply: viewPly, interaction: interaction)
    if case .wrong = feedback { h.selected = interaction.selected }
    return h
  }
}

/// Round ◀ / ▶ button for stepping through moves.
struct StepButton: View {
  let systemImage: String
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(.title3).weight(.bold))
        .frame(width: 48, height: 44)
        .foregroundStyle(Palette.textPrimary.opacity(enabled ? 1 : 0.3))
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surfaceRaised))
    }
    .disabled(!enabled)
  }
}


/// Your move vs the better one, and the habit that catches it (scrolls inside a fixed height).
struct InsightCard: View {
  let insight: MoveInsight

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.s) {
        row("Your move", insight.played, color: MoveClass.mistake.color)
        row("Better", insight.better, color: Palette.success)
        row("Why it was easy to miss", insight.habit, color: Palette.textSecondary)
      }
      .padding(Spacing.m)
    }
    .frame(height: 150)
    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surfaceRaised))
    .padding(.horizontal, Spacing.m)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("insight-card")
  }

  private func row(_ title: String, _ text: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased()).font(.system(.caption2).weight(.bold)).foregroundStyle(color)
      Text(text).font(.system(.callout)).foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
