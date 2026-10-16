import ChessCoachKit
import ChessKit
import SwiftUI

/// Outcome of one puzzle, reported to the runner.
struct PuzzleOutcome: Equatable {
  var solvedCleanly: Bool
  var ratingChange: TrainingService.RatingChange?
}

/// One puzzle in chess.com's puzzle style: prompt bar, board, feedback, hint/next.
struct PuzzleView: View {
  let puzzle: Puzzle
  /// Nil for normal puzzles; set when this is a spaced-repetition review.
  var review: ReviewItem? = nil
  var hasSetupMove = true
  /// false for placement: no rating or review updates.
  var rated = true
  let onFinished: (PuzzleOutcome) -> Void

  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue

  @State private var session: PuzzleSession?
  @State private var interaction = BoardInteraction()
  @State private var feedback: Feedback = .prompt
  @State private var annotations = AnnotationLayer()
  @State private var hintText: String?
  @State private var started = Date()
  @State private var change: TrainingService.RatingChange?
  @State private var recorded = false
  @State private var ready = false

  enum Feedback: Equatable {
    case prompt, correct, wrong(String), solved, revealed
  }

  var body: some View {
    VStack(spacing: 0) {
      promptBar
      ZStack {
        if let session {
          BoardView(
            position: session.game.position,
            highlights: highlights(session),
            annotations: annotations,
            theme: BoardTheme.named(themeID),
            pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
            flipped: session.userColor == .black,
            interactive: ready && feedback != .solved && feedback != .revealed,
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
        } else {
          Color.clear.aspectRatio(1, contentMode: .fit)
        }
      }
      feedbackBar
      Spacer(minLength: 0)
      controls
    }
    .task(id: puzzle.id) { await start() }
  }

  // MARK: - Pieces

  private var promptBar: some View {
    HStack(spacing: Spacing.s) {
      let color = session?.userColor ?? .white
      RoundedRectangle(cornerRadius: 3)
        .fill(color == .white ? Color.white : Color.black)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(ChessChrome.textSecondary, lineWidth: 1))
        .frame(width: 18, height: 18)
      VStack(alignment: .leading, spacing: 1) {
        Text(review == nil ? "\(color == .white ? "White" : "Black") to move" : "Review: \(color == .white ? "White" : "Black") to move")
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(ChessChrome.textPrimary)
        Text(subtitle)
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(ChessChrome.textSecondary)
      }
      Spacer()
      if review == nil {
        Text("\(puzzle.rating)")
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(ChessChrome.textSecondary)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(Capsule().fill(ChessChrome.card))
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
      case .correct: return ("checkmark.circle.fill", "Best move! Keep going…", ChessChrome.accentGreen)
      case .wrong(let san): return ("xmark.circle.fill", "\(san) isn't it. Try again.", ChessChrome.lowTime)
      case .solved:
        let delta = change.map { $0.delta >= 0 ? " +\($0.delta)" : " \($0.delta)" } ?? ""
        return ("checkmark.seal.fill", "Solved!\(delta)", ChessChrome.accentGreen)
      case .revealed: return ("eye.fill", "Here's the solution.", MoveClass.inaccuracy.color)
      }
    }()
    HStack(spacing: Spacing.s) {
      if !icon.isEmpty { Image(systemName: icon).font(.system(size: 20)) }
      Text(text).font(.system(size: 16, weight: .bold, design: .rounded))
        .accessibilityIdentifier("puzzle-feedback")
      Spacer()
    }
    .foregroundStyle(color)
    .padding(.horizontal, Spacing.l)
    .frame(height: 48)
    .animation(.easeOut(duration: 0.2), value: feedback)
  }

  @ViewBuilder
  private var controls: some View {
    HStack(spacing: Spacing.s) {
      if feedback == .solved || feedback == .revealed {
        PuzzleButton(title: "Next", systemImage: "arrow.right", prominent: true) { finish() }
          .accessibilityIdentifier("puzzle-next")
      } else {
        PuzzleButton(title: "Hint", systemImage: "lightbulb") { hint() }
          .accessibilityIdentifier("puzzle-hint")
        if showSolutionButton {
          PuzzleButton(title: "Solution", systemImage: "eye") { reveal() }
            .accessibilityIdentifier("puzzle-solution")
        }
      }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .background(ChessChrome.bar)
  }

  private var showSolutionButton: Bool {
    if case .wrong = feedback { return true }
    return (session?.hintsUsed ?? 0) >= 3
  }

  // MARK: - Flow

  private func start() async {
    session = PuzzleSession(puzzle: puzzle, hasSetupMove: hasSetupMove)
    ready = !hasSetupMove
    feedback = .prompt
    hintText = nil
    annotations = AnnotationLayer()
    interaction.reset()
    change = nil
    recorded = false
    if hasSetupMove {
      try? await Task.sleep(for: .milliseconds(450))
      // Mutate the live session (a hint tapped during the delay must not be lost).
      if var s = session, let setup = s.playSetup() {
        session = s
        playSound(for: setup, in: s)
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
    case .wrong:
      var trial = before
      if case .applied(let played) = trial.apply(from: from, to: to, promotion: trial.isPromotion(from: from, to: to) ? .queen : nil) {
        feedback = .wrong(played.san)
      }
      env.sounds.play(.illegal)
      session = s
    case .correct(let reply):
      session = s
      feedback = .correct
      hintText = nil
      annotations = AnnotationLayer()
      env.sounds.play(.move)
      if let reply { scheduleReplySound(reply, s) }
    case .solved:
      session = s
      feedback = .solved
      annotations = AnnotationLayer()
      env.sounds.play(.gameEnd)
      record(s)
    }
  }

  private func scheduleReplySound(_ reply: String, _ s: PuzzleSession) {
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      env.sounds.play(.move)
    }
  }

  private func hint() {
    guard ready, var s = session, let h = s.nextHint() else { return }
    session = s
    switch h {
    case .theme(let name): hintText = "Hint: look for a \(name.lowercased())."
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
    guard let s = session, let expected = s.expectedMove.flatMap(UCIMove.init) else { return }
    annotations.arrows = [Arrow(from: expected.from, to: expected.to, color: .green)]
    feedback = .revealed
    record(s)
  }

  private func record(_ s: PuzzleSession) {
    guard !recorded else { return }
    recorded = true
    guard rated else { return }
    let seconds = Date().timeIntervalSince(started)
    if let review {
      training.record(review: review, session: s, seconds: seconds)
    } else {
      change = training.record(puzzle: s, seconds: seconds)
    }
  }

  private func finish() {
    let clean = session.map { $0.isSolved && !$0.failedFirstTry && $0.hintsUsed == 0 } ?? false
    onFinished(PuzzleOutcome(solvedCleanly: clean, ratingChange: change))
  }

  private func playSound(for uci: String, in s: PuzzleSession) {
    if let last = s.game.lastMove {
      env.sounds.play(SoundEvent.forMove(last, gameOver: false))
    } else {
      env.sounds.play(.move)
    }
  }

  private func highlights(_ s: PuzzleSession) -> BoardHighlights {
    var h = BoardHighlights.make(session: s.game, ply: s.game.history.count, interaction: interaction)
    if case .wrong = feedback { h.selected = interaction.selected }
    return h
  }
}

struct PuzzleButton: View {
  let title: String
  let systemImage: String
  var prominent = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 16, weight: .bold, design: .rounded))
        .frame(maxWidth: .infinity, minHeight: 48)
        .foregroundStyle(prominent ? .white : ChessChrome.textPrimary)
        .background(RoundedRectangle(cornerRadius: 10).fill(prominent ? ChessChrome.accentGreen : ChessChrome.card))
    }
  }
}
