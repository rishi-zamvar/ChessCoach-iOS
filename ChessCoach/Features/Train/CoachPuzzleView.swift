import ChessCoachKit
import ChessKit
import SwiftUI

/// How puzzles give feedback (spec W3): Coach plays it out and lets you find your own mistake;
/// Instant says right or wrong at once (Quick warm-up and Puzzle Rush always use Instant).
enum PuzzleMode: String, CaseIterable, Identifiable {
  case coach, instant
  var id: String { rawValue }
  var title: String { self == .coach ? "Coach" : "Instant" }
  static let key = "puzzle.mode"
  static var current: PuzzleMode { PuzzleMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .coach }
}

/// A Coach-mode puzzle: every move is played, the opponent answers with its best move, and when
/// the line ends you find which of your moves was the mistake, then the better move from there.
struct CoachPuzzleView: View {
  let puzzle: Puzzle
  var review: ReviewItem? = nil
  var hasSetupMove = true
  let onFinished: (PuzzleResult) -> Void

  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue
  @AppStorage(BoardSettings.coordinatesKey) private var showCoordinates = true

  @State private var run: CoachPuzzleRun?
  /// The "find the better move" step: a one-move puzzle from just before your mistake.
  @State private var fix: PuzzleSession?
  @State private var interaction = BoardInteraction()
  @State private var annotations = AnnotationLayer()
  @State private var busy = false
  @State private var message = ""
  @State private var tone: Tone = .neutral
  @State private var highlighted: Int?
  @State private var started = Date()
  @State private var change: TrainingService.RatingChange?
  @State private var recorded = false
  @State private var analyzing: AnalysisRequest?

  enum Tone { case neutral, good, bad }

  private var engine: PuzzleEngine? { PuzzleEngine(env) }

  var body: some View {
    VStack(spacing: 0) {
      promptBar
      board
      messageBar
      if run?.phase == .done { ThumbsRow(surface: "coach_puzzle", context: ["puzzle": .string(puzzle.id)]) }
      if let run, run.phase != .playing { movesStrip(run) }
      Spacer(minLength: 0)
      controls
    }
    .task(id: puzzle.id) { await start() }
    .fullScreenCover(item: $analyzing) { AnalysisBoardView(request: $0) }
  }

  // MARK: - Pieces

  private var game: GameSession { fix?.game ?? run?.game ?? GameSession(startFEN: puzzle.fen) }
  private var userColor: Piece.Color { run?.userColor ?? .white }

  private var promptBar: some View {
    HStack(spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: 1) {
        Text("\(userColor == .white ? "White" : "Black") to move")
          .font(Typography.bodyEmph).foregroundStyle(Palette.textPrimary)
        Text(subtitle).font(Typography.footnote).foregroundStyle(Palette.textSecondary)
      }
      Spacer()
      if userColor == .black {
        Text("You play Black")
          .font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.actionLabel)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(Capsule().fill(Palette.action))
      }
      Text("Coach mode")
        .font(Typography.caption.weight(.semibold)).foregroundStyle(Palette.sage)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Palette.sageSoft))
        .accessibilityIdentifier("coach-mode-chip")
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
  }

  private var subtitle: String {
    switch run?.phase {
    case .findMistake: "Which of your moves was the mistake?"
    case .fixMistake: "Find the better move"
    default: "Play it out. You'll hear at the end how it went."
    }
  }

  private var board: some View {
    BoardView(
      position: game.position,
      highlights: BoardHighlights.make(session: game, ply: game.history.count, interaction: interaction),
      annotations: annotations,
      theme: BoardTheme.named(themeID),
      pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
      flipped: userColor == .black,
      showCoordinates: showCoordinates,
      interactive: canMove,
      onTap: { square in
        if case .move(let from, let to) = interaction.tap(square, session: game, userColor: userColor) { submit(from: from, to: to) }
      },
      onDragBegan: { interaction.dragBegan(at: $0, session: game, userColor: userColor) },
      onDragEnded: { square in
        if case .move(let from, let to) = interaction.dragEnded(at: square, session: game, userColor: userColor) { submit(from: from, to: to) }
      },
      onDragCancelled: { interaction.dragCancelled() },
      onArrow: { annotations.toggleUserArrow(from: $0, to: $1) }
    )
    .accessibilityIdentifier("coach-board")
  }

  private var canMove: Bool {
    guard !busy, let run else { return false }
    switch run.phase {
    case .playing: return !run.awaitingOpponent
    case .fixMistake: return fix?.isSolved == false
    default: return false
    }
  }

  private var messageBar: some View {
    HStack(spacing: Spacing.s) {
      if busy { ProgressView().controlSize(.small) }
      Text(message)
        .font(Typography.bodyEmph)
        .foregroundStyle(tone == .good ? Palette.success : tone == .bad ? Palette.danger : Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("coach-message")
      Spacer()
    }
    .padding(.horizontal, Spacing.l)
    .frame(minHeight: 52)
  }

  /// Your moves as chips: tap the one that went wrong.
  private func movesStrip(_ run: CoachPuzzleRun) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.s) {
        ForEach(Array(run.moves.enumerated()), id: \.offset) { i, move in
          Button { pick(i) } label: {
            Text("\(i + 1). \(move.san)")
              .font(Typography.moveSAN.weight(.semibold))
              .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
              .foregroundStyle(highlighted == i ? Palette.actionLabel : Palette.textPrimary)
              .background(Capsule().fill(highlighted == i ? MoveQuality.mistake.color : Palette.surfaceRaised))
              .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.75))
          }
          .buttonStyle(.plain)
          .disabled(run.phase != .findMistake)
          .accessibilityLabel("Your move \(i + 1), \(move.san)")
          .accessibilityIdentifier("coach-move-\(i)")
        }
      }
      .padding(.horizontal, Spacing.m)
    }
  }

  @ViewBuilder private var controls: some View {
    HStack(spacing: Spacing.s) {
      switch run?.phase {
      case .solved, .done:
        ActionButton(title: "Retry", systemImage: "arrow.counterclockwise") { Task { await start() } }
        ActionButton(title: "Analyze", systemImage: "magnifyingglass") { openAnalysis() }
          .accessibilityIdentifier("puzzle-analyze")
        ActionButton(title: "Next", systemImage: "arrow.right", prominent: true) { finish() }
          .accessibilityIdentifier("puzzle-next")
      case .fixMistake:
        ActionButton(title: "Hint", systemImage: "lightbulb") { hint() }
          .accessibilityIdentifier("puzzle-hint")
        ActionButton(title: "Show me", systemImage: "eye") { showFix() }
          .accessibilityIdentifier("puzzle-solution")
      default:
        ActionButton(title: "Analyze", systemImage: "magnifyingglass") { openAnalysis() }.hidden()
      }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .background(Palette.surfaceRaised)
  }

  // MARK: - Flow

  private func start() async {
    var r = CoachPuzzleRun(puzzle: puzzle, hasSetupMove: hasSetupMove)
    fix = nil
    highlighted = nil
    annotations = AnnotationLayer()
    interaction.reset()
    recorded = false
    change = nil
    message = ""
    tone = .neutral
    run = r
    if hasSetupMove {
      try? await Task.sleep(for: .milliseconds(450))
      r.playSetup()
      run = r
      if let last = r.game.lastMove { env.sounds.play(SoundEvent.forMove(last, gameOver: false)) }
    }
    started = Date()
  }

  private func submit(from: Square, to: Square) {
    guard let run else { return }
    var s = game
    let promo: Piece.Kind? = s.isPromotion(from: from, to: to) ? .queen : nil
    guard case .applied(let played) = s.apply(from: from, to: to, promotion: promo) else { return }
    interaction.reset()
    if case .fixMistake = run.phase { return submitFix(played) }
    Task { await play(played, before: run.game.position.fen) }
  }

  /// Plays your move (graded by the engine) and the opponent's best answer.
  private func play(_ played: PlayedMove, before fen: String) async {
    guard var r = run else { return }
    let onLine = r.game.history.count < puzzle.moves.count && puzzle.moves[r.game.history.count] == played.uci
    busy = true
    let loss = onLine ? 0 : await engine?.loss(fen: fen, uci: played.uci) ?? 0
    busy = false
    guard r.play(uci: played.uci, loss: loss) else { return }
    run = r
    env.sounds.play(SoundEvent.forMove(played, gameOver: r.game.isOver))
    if r.phase != .playing { return lineEnded() }
    // The opponent answers: the puzzle's move while you're on its line, otherwise the engine's best.
    let index = r.game.history.count
    let scripted = r.moves.allSatisfy { $0.loss == 0 } && index < puzzle.moves.count ? puzzle.moves[index] : nil
    busy = true
    let reply: String?
    if let scripted { reply = scripted } else { reply = await engine?.best(r.game.position.fen)?.pv.first }
    try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 500))
    busy = false
    guard let reply, var latest = run else { return lineEnded() }
    latest.opponentPlays(uci: reply)
    run = latest
    if let last = latest.game.lastMove { env.sounds.play(SoundEvent.forMove(last, gameOver: latest.game.isOver)) }
    if latest.phase != .playing { lineEnded() }
  }

  private func lineEnded() {
    guard let run else { return }
    switch run.phase {
    case .solved:
      message = "Solved. Every move held up."
      tone = .good
      Haptics.success()
      record()
    case .findMistake:
      message = "One of your moves was a mistake. Can you find which?"
      tone = .neutral
      Haptics.warning()
    default: break
    }
  }

  private func pick(_ index: Int) {
    guard var r = run else { return }
    let result = r.pick(index)
    run = r
    switch result {
    case .notThat:
      message = "Not that one. The position was still fine after it."
      tone = .bad
    case .found(let fen):
      highlighted = index
      message = "That's the one. Now find the better move."
      tone = .good
      Task { await startFix(fen: fen) }
    case .revealed(let i):
      highlighted = i
      message = "It was move \(i + 1), \(r.moves[i].san). Now find the better move."
      tone = .neutral
      Task { await startFix(fen: r.moves[i].fenBefore) }
    }
  }

  /// Rewinds to just before the mistake; the better move is the engine's (or the puzzle's) best.
  private func startFix(fen: String) async {
    busy = true
    let best: String?
    if fen == run?.moves.first?.fenBefore, let first = puzzle.moves.dropFirst(hasSetupMove ? 1 : 0).first {
      best = first
    } else {
      best = await engine?.best(fen)?.pv.first
    }
    busy = false
    guard let best else { return }
    let one = Puzzle(
      id: puzzle.id + ":fix", fen: fen, moves: [best], rating: puzzle.rating, rd: puzzle.rd, popularity: puzzle.popularity,
      themes: puzzle.themes, primaryTheme: puzzle.primaryTheme, opening: nil)
    fix = PuzzleSession(puzzle: one, hasSetupMove: false)
    annotations = AnnotationLayer()
  }

  private func submitFix(_ played: PlayedMove) {
    guard var f = fix else { return }
    let fen = f.game.position.fen
    switch f.submit(uci: played.uci) {
    case .solved, .correct:
      fix = f
      fixed("Better. That's the move.")
    case .wrong:
      fix = f
      Task {
        busy = true
        defer { busy = false }
        if let expected = f.expectedMove, let engine, await engine.alsoWins(fen: fen, uci: played.uci, solution: expected), var g = fix,
          g.acceptAlternative(uci: played.uci)
        {
          fix = g
          return fixed("Good move, that works too.")
        }
        message = (await engine?.refutation(fen: fen, wrong: played.uci)?.caption).map { "\($0) Try again." } ?? "\(played.san) isn't it. Try again."
        tone = .bad
        Haptics.warning()
      }
    case .ignored: break
    }
  }

  private func fixed(_ text: String) {
    guard var r = run else { return }
    r.fixed()
    run = r
    message = text + " " + gradeLine(r)
    tone = .good
    annotations = AnnotationLayer()
    Haptics.success()
    record()
  }

  private func hint() {
    guard var f = fix, var r = run, let h = f.nextHint() else { return }
    r.useHint()
    fix = f
    run = r
    switch h {
    case .theme(let name): message = name.isEmpty ? "Hint: check every capture and threat." : "Hint: look for a \(name.lowercased())."
    case .piece(let square):
      message = "Hint: move the highlighted piece."
      annotations.circles = [square: .blue]
    case .move(let from, let to):
      message = "The move is shown."
      annotations.circles = [:]
      annotations.arrows = [Arrow(from: from, to: to, color: .green)]
    }
  }

  private func showFix() {
    guard var r = run, let f = fix, let best = f.expectedMove.flatMap(UCIMove.init) else { return }
    r.revealFix()
    run = r
    annotations = AnnotationLayer()
    annotations.arrows = [Arrow(from: best.from, to: best.to, color: .green)]
    let san = FactExtractor.sanLine(fen: f.game.position.fen, ucis: [f.puzzle.moves[0]]).first ?? ""
    message = "The better move was \(san). It's added to your reviews."
    tone = .neutral
    record()
  }

  private func gradeLine(_ r: CoachPuzzleRun) -> String {
    switch r.coachGrade {
    case .selfFound: "You found your own mistake. That's how it sticks."
    case .assisted: "Worth another look soon."
    default: ""
    }
  }

  private func record() {
    guard !recorded, let run else { return }
    recorded = true
    let seconds = Date().timeIntervalSince(started)
    if let review {
      training.record(review: review, session: run, seconds: seconds)
    } else {
      change = training.record(puzzle: run, seconds: seconds)
    }
    env.telemetry.event("puzzle.done", metadata: [
      "id": .string(puzzle.id), "theme": .string(puzzle.primaryTheme), "rating": .int(puzzle.rating), "mode": .string("coach"),
      "grade": .string(run.coachGrade.rawValue), "hints": .int(run.hintsUsed), "secs": .double(seconds.rounded()),
      "first_move_ok": .bool(run.ratingScore > 0),
    ])
  }

  private func finish() {
    let clean = run?.coachGrade == .clean
    onFinished(PuzzleResult(solvedCleanly: clean, ratingChange: change))
  }

  private func openAnalysis() {
    guard let run else { return }
    let setup = hasSetupMove ? 1 : 0
    let start = run.game.fen(atPly: min(setup, run.game.history.count))
    env.telemetry.event("analysis.open", metadata: ["from": .string("coach_puzzle")])
    analyzing = AnalysisRequest(
      startFEN: start, moves: run.game.history.dropFirst(setup).map(\.uci), flipped: userColor == .black, title: "Analyze puzzle")
  }
}
