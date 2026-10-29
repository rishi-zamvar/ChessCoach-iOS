import ChessCoachKit
import ChessKit
import SwiftUI

/// Board-vision and safety drills:
/// - coordinates: "Tap e4" on an empty board
/// - checksCaptures: tap every piece that can give check or capture
/// - safeMove: is the arrowed move safe, or a blunder?
struct VisionDrillView: View {
  let kind: DrillKind
  let onFinished: (_ correct: Int, _ total: Int) -> Void

  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue

  @State private var round = 0
  @State private var correct = 0
  @State private var started = Date()
  // coordinates
  @State private var targets: [Square] = []
  @State private var flash: (Square, Bool)?
  // checks & captures
  @State private var cctFENs: [String] = []
  @State private var tapped: Set<Square> = []
  @State private var revealed = false
  // safe move
  @State private var questions: [BoardVision.SafetyQuestion] = []
  @State private var answer: Bool?
  /// After answering: how many moves of the question's line are played out on the board.
  @State private var lineStep = 0

  private var total: Int {
    switch kind {
    case .coordinates: 12
    case .checksCaptures: min(5, cctFENs.count)
    case .safeMove: min(8, questions.count)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      prompt
      board
      if kind == .safeMove { explanation }
      footer
      Spacer(minLength: 0)
    }
    .task { prepare() }
  }

  // MARK: - Prompt

  private var prompt: some View {
    VStack(spacing: 4) {
      Text(title).font(.system(.footnote).weight(.semibold)).foregroundStyle(Palette.textSecondary)
      Text(question)
        .font((kind == .coordinates ? Font.largeTitle : Font.body).weight(.bold))
        .foregroundStyle(Palette.textPrimary)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("drill-question")
      Text("\(min(round + 1, max(total, 1))) / \(max(total, 1)) · \(correct) correct")
        .font(.system(.caption)).foregroundStyle(Palette.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.m)
  }

  private var title: String {
    switch kind {
    case .coordinates: "Board vision"
    case .checksCaptures: "Checks & captures"
    case .safeMove: "Blunder check"
    }
  }

  private var question: String {
    switch kind {
    case .coordinates:
      return round < targets.count ? targets[round].notation : ""
    case .checksCaptures:
      guard round < cctFENs.count, let side = Position(fen: cctFENs[round])?.sideToMove else { return "" }
      return revealed ? "Every check and capture, shown with arrows." : "Tap every \(side == .white ? "White" : "Black") piece that can give check or capture."
    case .safeMove:
      guard round < questions.count else { return "" }
      if let answer {
        let q = questions[round]
        let right = answer == q.isSafe
        return right ? (q.isSafe ? "Right — it's safe." : "Right — it's a blunder.") : (q.isSafe ? "It was safe." : "It's a blunder — see the red reply.")
      }
      return "Is the arrowed move safe?"
    }
  }

  /// Below the board (so the board never shifts): why it's a blunder / safe, and the played-out move.
  private var explanation: some View {
    ScrollView {
      VStack(spacing: 4) {
        if answer != nil, round < questions.count {
          Text(questions[round].why)
            .font(.system(.subheadline).weight(.medium)).foregroundStyle(Palette.textPrimary)
            .accessibilityIdentifier("drill-why")
          if let caption = lineCaption {
            Text(caption).font(.system(.footnote)).foregroundStyle(Palette.textSecondary)
              .accessibilityIdentifier("drill-line-caption")
          }
        }
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, Spacing.m)
      .padding(.top, Spacing.s)
    }
    .frame(height: 84)
  }

  // MARK: - Board

  @ViewBuilder
  private var board: some View {
    switch kind {
    case .coordinates:
      BoardView(
        position: Position(fen: "8/8/8/8/8/8/8/8 w - - 0 1") ?? .standard,
        highlights: BoardHighlights(selected: flash.map { $0.0 }),
        annotations: {
          var a = AnnotationLayer()
          if let (square, ok) = flash { a.circles[square] = ok ? .green : .red }
          return a
        }(),
        theme: BoardTheme.named(themeID), showCoordinates: false,
        onTap: tapCoordinate)
    case .checksCaptures:
      if round < cctFENs.count {
        let fen = cctFENs[round]
        let position = Position(fen: fen) ?? .standard
        BoardView(
          position: position,
          highlights: BoardHighlights(lastMove: Array(tapped)),
          annotations: revealed ? cctAnnotations(fen) : AnnotationLayer(),
          theme: BoardTheme.named(themeID), pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
          flipped: position.sideToMove == .black,
          onTap: { square in
            guard !revealed, position.piece(at: square)?.color == position.sideToMove else { return }
            if tapped.contains(square) { tapped.remove(square) } else { tapped.insert(square) }
            Haptics.selection()
          })
      }
    case .safeMove:
      if round < questions.count {
        let q = questions[round]
        let position = Position(fen: q.fen) ?? .standard
        let shown = playedOut(q)
        BoardView(
          position: shown.position,
          highlights: BoardHighlights(lastMove: shown.history.last.map { [$0.move.start, $0.move.end] } ?? []),
          annotations: safeAnnotations(q),
          theme: BoardTheme.named(themeID), pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
          flipped: position.sideToMove == .black, interactive: false)
      }
    }
  }

  @ViewBuilder
  private var footer: some View {
    HStack(spacing: Spacing.s) {
      switch kind {
      case .coordinates:
        EmptyView()
      case .checksCaptures:
        if revealed {
          ActionButton(title: "Next", systemImage: "arrow.right", prominent: true) { next() }
        } else {
          ActionButton(title: "Check", systemImage: "checkmark", prominent: true) { checkCCT() }
            .accessibilityIdentifier("drill-check")
        }
      case .safeMove:
        if answer == nil {
          ActionButton(title: "Safe", systemImage: "checkmark.shield", prominent: true) { answerSafe(true) }
            .accessibilityIdentifier("drill-safe")
          ActionButton(title: "Blunder", systemImage: "exclamationmark.triangle") { answerSafe(false) }
            .accessibilityIdentifier("drill-blunder")
        } else {
          let q = questions[round]
          ActionButton(title: "", systemImage: "chevron.left") { lineStep = max(0, lineStep - 1) }
            .frame(maxWidth: 56).disabled(lineStep == 0)
            .accessibilityIdentifier("drill-line-back")
          ActionButton(title: lineStep == 0 ? "Play it out" : "Next move", systemImage: "play.fill") {
            lineStep = min(q.line.count, lineStep + 1)
            if let last = playedOut(q).history.last { env.sounds.play(SoundEvent.forMove(last, gameOver: false)) }
          }
          .disabled(lineStep >= q.line.count)
          .accessibilityIdentifier("drill-line-forward")
          ActionButton(title: "Next", systemImage: "arrow.right", prominent: true) { next() }
        }
      }
    }
    .padding(Spacing.m)
  }

  // MARK: - Logic

  private func prepare() {
    started = Date()
    switch kind {
    case .coordinates:
      targets = BoardVision.coordinateTargets(count: 12, random: SystemRandom())
    case .checksCaptures:
      let pool = (try? training.puzzles?.puzzles(theme: "hangingPiece", around: 900, excluding: [], limit: 12)) ?? nil
      cctFENs = (pool ?? []).compactMap { p -> String? in
        var s = GameSession(startFEN: p.fen)
        s.apply(uci: p.moves[0])
        return BoardVision.checksAndCaptures(fen: s.position.fen).isEmpty ? nil : s.position.fen
      }
    case .safeMove:
      let pool = (try? training.puzzles?.puzzles(theme: nil, around: max(600, training.globalRating), excluding: [], limit: 8)) ?? nil
      // Alternate unsafe and safe so guessing doesn't pay.
      questions = (pool ?? []).enumerated().compactMap { i, p in
        let pair = BoardVision.safetyQuestions(from: p)
        return pair.count == 2 ? pair[i % 2] : nil
      }
    }
    if total == 0 { onFinished(0, 0) }
  }

  private func tapCoordinate(_ square: Square) {
    guard round < targets.count, flash == nil else { return }
    let ok = square == targets[round]
    if ok { correct += 1 }
    flash = (square, ok)
    env.sounds.play(ok ? .move : .illegal)
    Task {
      try? await Task.sleep(for: .milliseconds(ok ? 250 : 600))
      flash = nil
      next()
    }
  }

  private func cctAnswer(_ fen: String) -> Set<Square> {
    Set(BoardVision.checksAndCaptures(fen: fen).compactMap { UCIMove($0)?.from })
  }

  private func cctAnnotations(_ fen: String) -> AnnotationLayer {
    var a = AnnotationLayer()
    for uci in BoardVision.checksAndCaptures(fen: fen) {
      if let m = UCIMove(uci) { a.arrows.append(Arrow(from: m.from, to: m.to, color: .green)) }
    }
    for missed in cctAnswer(fen).subtracting(tapped) { a.circles[missed] = .red }
    return a
  }

  private func checkCCT() {
    guard round < cctFENs.count else { return }
    let ok = tapped == cctAnswer(cctFENs[round])
    if ok { correct += 1 }
    env.sounds.play(ok ? .gameEnd : .illegal)
    revealed = true
  }

  private func safeAnnotations(_ q: BoardVision.SafetyQuestion) -> AnnotationLayer {
    var a = AnnotationLayer()
    if lineStep == 0 {
      if let m = UCIMove(q.move) { a.arrows.append(Arrow(from: m.from, to: m.to, color: .blue)) }
      if answer != nil, let r = q.refutation.flatMap(UCIMove.init) { a.arrows.append(Arrow(from: r.from, to: r.to, color: .red)) }
    } else if lineStep < q.line.count, let m = UCIMove(q.line[lineStep]) {
      // Playing it out: the arrow shows what comes next.
      a.arrows.append(Arrow(from: m.from, to: m.to, color: lineStep % 2 == 0 ? .blue : .red))
    }
    return a
  }

  /// The question's position with the first `lineStep` moves of its line played.
  private func playedOut(_ q: BoardVision.SafetyQuestion) -> GameSession {
    var game = GameSession(startFEN: q.fen)
    for uci in q.line.prefix(lineStep) { game.apply(uci: uci) }
    return game
  }

  /// What the last played-out move did, e.g. "Rd8# is checkmate."
  private var lineCaption: String? {
    guard lineStep > 0, round < questions.count else { return nil }
    let q = questions[round]
    var before = GameSession(startFEN: q.fen)
    for uci in q.line.prefix(lineStep - 1) { before.apply(uci: uci) }
    return Explainer.reason(fen: before.position.fen, uci: q.line[lineStep - 1])
  }

  private func answerSafe(_ safe: Bool) {
    guard round < questions.count else { return }
    let ok = safe == questions[round].isSafe
    if ok { correct += 1 }
    env.sounds.play(ok ? .move : .illegal)
    answer = safe
  }

  private func next() {
    tapped = []
    revealed = false
    answer = nil
    lineStep = 0
    if round + 1 >= total {
      training.recordDrill(kind, correct: correct, total: total, seconds: Date().timeIntervalSince(started))
      onFinished(correct, total)
    } else {
      round += 1
    }
  }
}
