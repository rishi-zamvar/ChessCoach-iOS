import ChessCoachKit
import ChessKit
import SwiftUI

/// Game Review: analyzes the game (or loads the stored analysis), then shows the
/// coach bubble, eval bar, board with arrows/badges, eval graph and summary.
struct ReviewScreen: View {
  let game: GameRecord
  @Environment(\.dismiss) private var dismiss
  @Environment(AnalysisService.self) private var analysisService
  @Environment(AppEnvironment.self) private var env
  @State private var controller: ReviewController?
  @State private var failure: String?
  @State private var flipped = false
  @State private var analyzing: AnalysisRequest?
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue

  var body: some View {
    VStack(spacing: 0) {
      header
      if let controller {
        if analysisService.progress?.gameID == game.id {
          ProgressView(value: analysisService.progress?.fraction ?? 0) {
            Text(env.server.isOnline ? "Deep analysis on your home PC…" : "Deep analysis…").font(.system(.caption)).foregroundStyle(Palette.textSecondary)
          }
          .tint(Palette.sage)
          .padding(.horizontal, Spacing.m)
        } else if env.server.canDeepAnalyze, !controller.analysis.engine.contains("pc") {
          Button {
            Task { await deepen() }
          } label: {
            Label(env.server.isOnline ? "Deeper analysis on your home PC" : "Deeper analysis", systemImage: env.server.isOnline ? "desktopcomputer" : "cpu")
              .font(.system(.footnote).weight(.semibold))
              .foregroundStyle(Palette.sage)
          }
          .padding(.top, Spacing.xs)
          .accessibilityIdentifier("review-deep")
        }
        ReviewContent(
          controller: controller, flipped: flipped, theme: BoardTheme.named(themeID),
          pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default)
      } else if let failure {
        Spacer()
        Text(failure).foregroundStyle(Palette.textSecondary).padding()
        Spacer()
      } else {
        AnalyzingView(progress: analysisService.progress)
      }
    }
    .background(Palette.surfaceBase.ignoresSafeArea())
    .fullScreenCover(item: $analyzing) { AnalysisBoardView(request: $0) }
    .screen("review", context: ["game": .string(game.id)], board: true)
    .task { await load() }
    .onAppear { analysisService.beginForegroundEngineUse() }
    .onDisappear { analysisService.endForegroundEngineUse() }
  }

  private var header: some View {
    HStack {
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(Typography.symbol(16, weight: .semibold)).frame(width: 44, height: 44)
      }
      .accessibilityIdentifier("review-close")
      .accessibilityLabel("Close")
      Spacer()
      Text("Game Review").font(Typography.bodyEmph).foregroundStyle(Palette.textPrimary)
      Spacer()
      FeedbackButton()
      if let controller {
        Button {
          env.telemetry.event("analysis.open", metadata: ["from": .string("review")])
          analyzing = AnalysisRequest(
            startFEN: controller.session.startFEN, moves: controller.session.history.prefix(controller.ply).map(\.uci),
            flipped: flipped, title: "Analyze from here")
        } label: {
          Image(systemName: "magnifyingglass").font(Typography.symbol(15, weight: .semibold)).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Analyze this position")
        .accessibilityIdentifier("review-analyze")
      }
      Button { flipped.toggle() } label: {
        Image(systemName: "arrow.up.arrow.down").font(Typography.symbol(15, weight: .semibold)).frame(width: 44, height: 44)
      }
      .accessibilityLabel("Flip board")
    }
    .foregroundStyle(Palette.textSecondary)
    .padding(.horizontal, Spacing.s)
    .background(Palette.surfaceRaised)
  }

  private func deepen() async {
    guard let session = GameSession(pgn: game.pgn) else { return }
    if let deep = try? await analysisService.deepAnalyze(game) {
      controller = ReviewController(analysis: deep, session: session, telemetry: env.telemetry)
    }
  }

  private func load() async {
    flipped = game.userColor == "black"
    guard let session = GameSession(pgn: game.pgn) else {
      failure = "This game's PGN couldn't be read."
      return
    }
    do {
      let analysis = try await analysisService.analysis(for: game)
      controller = ReviewController(analysis: analysis, session: session, telemetry: env.telemetry)
    } catch is CancellationError {
      return
    } catch {
      failure = env.engineHost == nil ? "Engines are missing from this build." : "Analysis failed. Try again."
    }
  }
}

/// Spinner + progress while the engine runs.
private struct AnalyzingView: View {
  let progress: AnalysisService.Progress?

  var body: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      Image(systemName: "sparkle.magnifyingglass")
        .font(Typography.symbol(44))
        .foregroundStyle(Palette.sage)
        .symbolEffect(.pulse)
      Text("Analyzing your game…")
        .font(.system(.title3).weight(.bold))
        .foregroundStyle(Palette.textPrimary)
      if let progress, progress.total > 1 {
        ProgressView(value: progress.fraction)
          .tint(Palette.sage)
          .frame(maxWidth: 240)
        Text(detail(progress))
          .font(.system(.footnote))
          .foregroundStyle(Palette.textSecondary)
          .monospacedDigit()
      } else {
        ProgressView().tint(Palette.textSecondary)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier("review-analyzing")
  }

  private func detail(_ p: AnalysisService.Progress) -> String {
    var text = "Position \(p.done) of \(p.total)"
    if let eta = p.etaSeconds, p.fraction < 1 {
      text += " · ~\(max(1, Int(eta * (1 - p.fraction))))s left"
    }
    return text
  }
}

/// The loaded review.
private struct ReviewContent: View {
  @Bindable var controller: ReviewController
  @Environment(AppEnvironment.self) private var env
  /// AI-rewritten explanations by ply (template text shows until one arrives).
  @State private var aiText: [Int: String] = [:]
  @State private var askingCoach = false
  @State private var coachArrows: [Arrow] = []
  @State private var practice: PracticeRun?

  struct PracticeRun: Identifiable {
    let id = UUID()
    let title: String
    let tasks: [TrainingTask]
  }
  let flipped: Bool
  let theme: BoardTheme
  let pieceSet: PieceSetID

  var body: some View {
    VStack(spacing: 0) {
      // Fixed height: long explanations scroll inside, so the board never shifts.
      ScrollView {
        CoachBubble(text: bubbleText, move: controller.retryState == nil ? controller.currentMove : nil)
          .padding(.horizontal, Spacing.m)
          .padding(.vertical, Spacing.s)
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(height: 132)
      .animation(.easeOut(duration: 0.2), value: controller.coachText)
      HStack(spacing: 0) {
        EvalBar(whiteWin: controller.analysis.whiteWin[safe: displayedPly] ?? 50, flipped: flipped)
          .frame(width: 14)
        BoardView(
          position: Position(fen: controller.displayedFEN) ?? .standard,
          highlights: controller.highlights,
          annotations: {
            var layer = controller.annotations
            layer.arrows += coachArrows
            return layer
          }(),
          theme: theme,
          pieceSet: pieceSet,
          flipped: flipped,
          interactive: controller.retryState != nil,
          onTap: { controller.retryTap($0) },
          onDragBegan: { square in
            guard controller.retryState != nil, let piece = Position(fen: controller.displayedFEN)?.piece(at: square) else { return false }
            dragFrom = square
            return piece.color == Position(fen: controller.displayedFEN)?.sideToMove
          },
          onDragEnded: { to in
            if let from = dragFrom, let to { controller.retryDrag(from: from, to: to) }
            dragFrom = nil
          },
          onDragCancelled: { dragFrom = nil },
          badge: badge
        )
      }
      ScrollView {
        VStack(spacing: Spacing.m) {
          EvalGraph(
            whiteWin: controller.analysis.whiteWin, moments: controller.keyMoments, current: controller.ply,
            moves: controller.analysis.moves
          ) { controller.goTo(ply: $0) }
          .frame(height: 64)
          if controller.retryState == nil, controller.line == nil, let insight = userInsight {
            insightBlock(insight)
          }
          ReviewMoveList(moves: controller.analysis.moves, current: controller.ply) { controller.goTo(ply: $0) }
          if let note = repertoireNote {
            HStack(alignment: .top, spacing: Spacing.s) {
              Image(systemName: "book.closed").foregroundStyle(MoveClass.book.color)
              Text(note.text).font(.system(.callout).weight(.medium)).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 0)
              if let ply = note.ply {
                Button("Show") { controller.goTo(ply: ply) }
                  .font(.system(.footnote).weight(.bold)).foregroundStyle(Palette.sage)
              }
            }
            .padding(Spacing.m)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surfaceRaised))
            .accessibilityIdentifier("repertoire-note")
          }
          SummaryCard(analysis: controller.analysis)
        }
        .padding(Spacing.m)
      }
      controls
    }
    .task(id: controller.ply) {
      coachArrows = []
      await loadAIExplanation()
    }
    .fullScreenCover(item: $practice) { run in
      TrainingRunnerView(title: run.title, tasks: run.tasks)
    }
    .sheet(isPresented: $askingCoach) {
      AskCoachSheet(
        fen: controller.displayedFEN,
        history: controller.analysis.moves.prefix(controller.ply).map(\.san),
        suggestions: ["Why was this move bad?", "What was the better plan?", "What should I have noticed?"]
      ) { coachArrows = $0 }
      .presentationDetents([.medium, .large])
    }
  }

  @State private var dragFrom: Square?
  @Environment(TrainingService.self) private var training

  /// Where this game left the learner's style repertoire (or the opponent left the book).
  private var repertoireNote: (text: String, ply: Int?)? {
    let analysis = controller.analysis
    let userColor: Piece.Color = analysis.userColor == "white" ? .white : .black
    let style = training.profile?.style.rawValue ?? "allRounder"
    let first = analysis.moves.first?.uci ?? ""
    let file: String =
      userColor == .white ? "\(style)-white" : (first == "e2e4" ? "\(style)-black-e4" : "\(style)-black-d4")
    guard let rep = RepertoireLibrary.forStyle(style).first(where: { $0.fileName == file }),
      let departure = rep.departure(gameMoves: analysis.moves.map(\.uci), userColor: userColor)
    else { return nil }
    let moveNumber = { (ply: Int) in "move \((ply + 1) / 2)" }
    switch departure {
    case .userLeft(let ply, let played, let expected):
      return ("You left your \(rep.name) at \(moveNumber(ply)): you played \(played), your line is \(expected.joined(separator: " or ")).", ply)
    case .opponentLeft(let ply, let played):
      return ("Your opponent left your repertoire at \(moveNumber(ply)) with \(played) — worth learning a reply.", ply)
    case .followedToEnd(let ply):
      return ("You followed your \(rep.name) for \((ply + 1) / 2) moves. Nice.", nil)
    }
  }

  private var bubbleText: String {
    if controller.retryState == nil, controller.line == nil, let ai = aiText[controller.ply] { return ai }
    return controller.coachText
  }

  /// Ask the AI to rewrite the current move's explanation (critical moves only; cached).
  private func loadAIExplanation() async {
    let ply = controller.ply
    guard aiText[ply] == nil, let move = controller.currentMove, move.label.isCritical || move.label.isError,
      let facts = move.facts
    else { return }
    let isUser = move.color == controller.analysis.userColor
    let result = await env.aiExplainer.explain(sheet: facts, label: move.label, isUser: isUser, template: move.explanation)
    if result.origin != .template {
      aiText[ply] = result.text
    } else if OnDeviceExplainer.isAvailable,
      let local = await OnDeviceExplainer.explain(sheet: facts, label: move.label, isUser: isUser, template: move.explanation)
    {
      aiText[ply] = local  // offline: Apple's on-device model, same grounding check
    }
  }

  /// Why your move was a mistake (your own moves only).
  private var userInsight: MoveInsight? {
    guard controller.currentMove?.color == controller.analysis.userColor else { return nil }
    return controller.insight
  }

  /// This kind of mistake across your analyzed games: (count, games).
  private func repeats(_ type: MistakeType) -> (count: Int, games: Int) {
    let ms = (try? env.analysisStore.mistakes(inPattern: AnalysisStore.typeKey(type))) ?? []
    return (ms.count, Set(ms.map(\.gameID)).count)
  }

  @ViewBuilder
  private func insightBlock(_ insight: MoveInsight) -> some View {
    let type = controller.currentMove?.mistakeType ?? .positional
    let seen = repeats(type)
    VStack(alignment: .leading, spacing: Spacing.s) {
      insightRow("Your move", insight.played, color: MoveClass.mistake.color)
      insightRow("Why the better move is better", insight.better, color: Palette.success)
      insightRow("Why you missed it", insight.habit, color: Palette.textSecondary)
      HStack(spacing: Spacing.s) {
        lineButton("Your line", better: false).accessibilityIdentifier("review-line-yours")
        lineButton("Better line", better: true).accessibilityIdentifier("review-line-better")
      }
      if seen.games >= 2 {
        Button {
          practice = PracticeRun(
            title: type.displayName, tasks: training.patternTasks(key: AnalysisStore.typeKey(type)))
        } label: {
          Label("\(type.displayName): \(seen.count) times in \(seen.games) games. Practice them", systemImage: "repeat")
            .font(.system(.footnote).weight(.bold)).foregroundStyle(Palette.sage)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("review-practice-pattern")
      }
    }
    .padding(Spacing.m)
    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surfaceRaised))
    // .contain keeps the buttons' own identifiers.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("review-insight")
  }

  private func insightRow(_ title: String, _ text: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased()).font(.system(.caption2).weight(.bold)).foregroundStyle(color)
      Text(text).font(.system(.callout)).foregroundStyle(Palette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func lineButton(_ title: String, better: Bool) -> some View {
    Button { controller.playLine(better: better) } label: {
      Label(title, systemImage: "play.fill")
        .font(.system(.footnote).weight(.bold))
        .foregroundStyle(better ? Palette.success : MoveClass.mistake.color)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(better ? Palette.success : MoveClass.mistake.color))
    }
  }

  private var displayedPly: Int { controller.retryState.map { $0.ply - 1 } ?? controller.ply }

  private var badge: SquareBadge? {
    guard controller.retryState == nil, let move = controller.currentMove, let uci = UCIMove(move.uci) else { return nil }
    return SquareBadge(square: uci.to, text: move.label.glyph, color: move.label.color)
  }

  @ViewBuilder
  private var controls: some View {
    HStack(spacing: Spacing.s) {
      if controller.retryState == nil, env.aiSettings.hasKey {
        ActionButton(title: "", systemImage: "bubble.left.and.text.bubble.right") { askingCoach = true }
          .frame(maxWidth: 56)
          .accessibilityIdentifier("review-ask")
      }
      if let line = controller.line {
        ActionButton(title: "Back", systemImage: "arrow.uturn.backward") { controller.endLine() }
          .accessibilityIdentifier("review-line-end")
        ActionButton(title: "", systemImage: "chevron.left") { controller.lineBack() }
          .frame(maxWidth: 56).disabled(line.step == 0)
        ActionButton(title: line.step == 0 ? "Play" : "Next move", systemImage: "play.fill", prominent: true) { controller.lineForward() }
          .disabled(line.step >= line.moves.count)
          .accessibilityIdentifier("review-line-forward")
      } else if let retry = controller.retryState {
        ActionButton(title: "Back", systemImage: "arrow.uturn.backward") { controller.endRetry() }
        if !retry.solved && !retry.revealed {
          ActionButton(title: "Hint", systemImage: "lightbulb") { controller.hint() }
          ActionButton(title: "Show", systemImage: "eye") { controller.reveal() }
        } else {
          ActionButton(title: "Next", systemImage: "forward.fill", prominent: true) {
            controller.endRetry()
            controller.nextMoment()
          }
        }
      } else if controller.ply == 0 {
        ActionButton(title: "Start Review", systemImage: "play.fill", prominent: true) { controller.startReview() }
          .accessibilityIdentifier("review-start")
      } else {
        ActionButton(title: "", systemImage: "chevron.left") { controller.stepBack() }
          .frame(maxWidth: 56)
        if controller.canRetry {
          ActionButton(title: "Retry", systemImage: "arrow.counterclockwise", prominent: true) { controller.retry() }
            .accessibilityIdentifier("review-retry")
          if userInsight == nil {
            ActionButton(title: "Next Moment", systemImage: "forward.fill") { controller.nextMoment() }
          }
        } else {
          ActionButton(title: "Next Moment", systemImage: "forward.fill", prominent: true) { controller.nextMoment() }
            .accessibilityIdentifier("review-next")
        }
        ActionButton(title: "", systemImage: "chevron.right") { controller.stepForward() }
          .frame(maxWidth: 56)
      }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .background(Palette.surfaceRaised)
  }
}


/// Coach avatar + speech bubble; tinted by the move's label.
private struct CoachBubble: View {
  let text: String
  let move: MoveAnalysis?

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      ZStack {
        Circle().fill(Palette.surfaceRaised)
        Text("♞").font(Typography.symbol(26, design: .serif)).foregroundStyle(Palette.sage)
      }
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 4) {
        if let move {
          HStack(spacing: 6) {
            Text(move.label.glyph)
              .font(.system(.caption2).weight(.heavy))
              .foregroundStyle(.white)
              .frame(width: 22, height: 22)
              .background(Circle().fill(move.label.color))
            Text(headline(move))
              .font(.system(.subheadline).weight(.bold))
              .foregroundStyle(move.label.color)
          }
        }
        Text(text)
          .font(.system(.callout).weight(.medium))
          .foregroundStyle(Palette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("coach-text")
      }
      .padding(Spacing.m)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surfaceRaised))
    }
    .frame(minHeight: 72, alignment: .top)
  }

  private func headline(_ move: MoveAnalysis) -> String {
    let san = move.san
    switch move.label {
    case .brilliant: return "\(san) is brilliant!"
    case .great: return "\(san) is a great move"
    case .best: return "\(san) is best"
    case .excellent: return "\(san) is excellent"
    case .good: return "\(san) is good"
    case .book: return "\(san) is a book move"
    case .forced: return "\(san) is forced"
    case .inaccuracy: return "\(san) is an inaccuracy"
    case .mistake: return "\(san) is a mistake"
    case .miss: return "\(san) is a miss"
    case .blunder: return "\(san) is a blunder"
    }
  }

}

/// Vertical eval bar (white share from the bottom when not flipped).
struct EvalBar: View {
  let whiteWin: Double
  let flipped: Bool

  var body: some View {
    GeometryReader { proxy in
      let whiteHeight = proxy.size.height * whiteWin / 100
      ZStack(alignment: flipped ? .top : .bottom) {
        Palette.evalBlack
        Rectangle().fill(Palette.evalWhite).frame(height: whiteHeight)
        Rectangle().fill(Palette.separatorStrong).frame(height: 0.5).frame(maxHeight: .infinity)
      }
      .animation(.easeOut(duration: 0.3), value: whiteWin)
    }
    .accessibilityLabel("Evaluation")
  }
}

/// Area chart of White's win% with key-moment dots; tap/drag to scrub.
struct EvalGraph: View {
  let whiteWin: [Double]
  let moments: [Int]
  let current: Int
  let moves: [MoveAnalysis]
  let onSelect: (Int) -> Void

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      let step = whiteWin.count > 1 ? w / CGFloat(whiteWin.count - 1) : w
      ZStack(alignment: .topLeading) {
        Palette.evalBlack
        Path { p in
          p.move(to: CGPoint(x: 0, y: h))
          for (i, v) in whiteWin.enumerated() {
            p.addLine(to: CGPoint(x: CGFloat(i) * step, y: h * (1 - v / 100)))
          }
          p.addLine(to: CGPoint(x: w, y: h))
          p.closeSubpath()
        }
        .fill(Palette.evalWhite)
        Path { p in
          p.move(to: CGPoint(x: 0, y: h / 2))
          p.addLine(to: CGPoint(x: w, y: h / 2))
        }
        .stroke(Palette.separatorStrong, lineWidth: 0.5)
        ForEach(moments, id: \.self) { ply in
          if ply < whiteWin.count, ply - 1 < moves.count {
            Circle()
              .fill(moves[ply - 1].label.color)
              .frame(width: 7, height: 7)
              .position(x: CGFloat(ply) * step, y: h * (1 - whiteWin[ply] / 100))
          }
        }
        Rectangle()
          .fill(Palette.sage)
          .frame(width: 2, height: h)
          .position(x: CGFloat(current) * step, y: h / 2)
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { value in
          let ply = Int((value.location.x / step).rounded())
          onSelect(max(0, min(whiteWin.count - 1, ply)))
        })
    }
    .accessibilityIdentifier("eval-graph")
  }
}

/// Two-column move list with label dots.
private struct ReviewMoveList: View {
  let moves: [MoveAnalysis]
  let current: Int
  let onSelect: (Int) -> Void

  struct Row: Identifiable {
    let id: Int
    let white: MoveAnalysis
    let black: MoveAnalysis?
  }

  private var rows: [Row] {
    stride(from: 0, to: moves.count, by: 2).map { i -> Row in
      let black: MoveAnalysis? = i + 1 < moves.count ? moves[i + 1] : nil
      return Row(id: i / 2 + 1, white: moves[i], black: black)
    }
  }

  var body: some View {
    VStack(spacing: 2) {
      ForEach(rows) { row in
        let white = row.white
        let black = row.black
        HStack(spacing: Spacing.s) {
          Text("\(row.id).").font(.system(.footnote)).foregroundStyle(Palette.textSecondary)
            .frame(width: 30, alignment: .leading)
          cell(white)
          if let black { cell(black) } else { Spacer().frame(maxWidth: .infinity) }
        }
      }
    }
    .padding(Spacing.s)
    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surfaceRaised))
  }

  private func cell(_ move: MoveAnalysis) -> some View {
    Button { onSelect(move.ply) } label: {
      HStack(spacing: 6) {
        Circle().fill(move.label.color).frame(width: 8, height: 8)
          .opacity(move.label == .good || move.label == .excellent || move.label == .best ? 0.5 : 1)
        Text(move.san)
          .font(Typography.moveSAN.weight(move.ply == current ? .bold : .medium))
          .foregroundStyle(move.ply == current ? Palette.textPrimary : Palette.textSecondary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 5).fill(move.ply == current ? Color.white.opacity(0.14) : .clear))
    }
    .buttonStyle(.plain)
  }
}

/// Accuracy, label counts and phase grades.
private struct SummaryCard: View {
  let analysis: GameAnalysis

  private let shown: [MoveClass] = [.brilliant, .great, .best, .excellent, .good, .book, .inaccuracy, .mistake, .miss, .blunder]

  var body: some View {
    VStack(spacing: Spacing.m) {
      if let opening = analysis.openingName {
        Text(opening).font(.system(.footnote).weight(.medium)).foregroundStyle(Palette.textSecondary)
      }
      HStack {
        accuracy("White", analysis.accuracyWhite)
        Spacer()
        Text("Accuracy").font(.system(.footnote).weight(.semibold)).foregroundStyle(Palette.textSecondary)
        Spacer()
        accuracy("Black", analysis.accuracyBlack)
      }
      let white = analysis.counts(for: "white")
      let black = analysis.counts(for: "black")
      ForEach(shown, id: \.self) { label in
        HStack {
          Text("\(white[label] ?? 0)").frame(width: 40).foregroundStyle(label.color)
          Spacer()
          HStack(spacing: 6) {
            Text(label.glyph).font(.system(.caption2).weight(.heavy)).foregroundStyle(.white)
              .frame(width: 20, height: 20).background(Circle().fill(label.color))
            Text(label.displayName).foregroundStyle(Palette.textPrimary)
          }
          Spacer()
          Text("\(black[label] ?? 0)").frame(width: 40).foregroundStyle(label.color)
        }
        .font(.system(.callout).weight(.semibold))
      }
      Divider().background(Palette.surfaceRaised)
      ForEach([GamePhaseKind.opening, .middlegame, .endgame], id: \.self) { phase in
        HStack {
          grade(analysis.phaseAccuracy(phase, color: "white"))
          Spacer()
          Text(phase.rawValue.capitalized).font(.system(.footnote).weight(.medium)).foregroundStyle(Palette.textSecondary)
          Spacer()
          grade(analysis.phaseAccuracy(phase, color: "black"))
        }
      }
    }
    .padding(Spacing.l)
    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surfaceRaised))
  }

  private func accuracy(_ side: String, _ value: Double?) -> some View {
    VStack(spacing: 2) {
      Text(value.map { String(format: "%.1f", $0) } ?? "–")
        .font(.system(.title2).weight(.heavy))
        .foregroundStyle(Palette.textPrimary)
      Text(side).font(.system(.caption2)).foregroundStyle(Palette.textSecondary)
    }
    .frame(width: 72)
  }

  private func grade(_ accuracy: Double?) -> some View {
    let (symbol, color): (String, Color) = {
      guard let a = accuracy else { return ("–", Palette.textSecondary) }
      switch a {
      case 85...: return ("★", MoveClass.best.color)
      case 70..<85: return ("👍", MoveClass.excellent.color)
      case 50..<70: return ("?!", MoveClass.inaccuracy.color)
      default: return ("??", MoveClass.blunder.color)
      }
    }()
    return Text(symbol).font(.system(.callout).weight(.bold)).foregroundStyle(color).frame(width: 72)
  }
}

extension MoveClass {
  /// The design-system quality (glyph + colour-blind-safe colour) for this label.
  var quality: MoveQuality {
    switch self {
    case .brilliant: .brilliant
    case .great: .great
    case .best: .best
    case .excellent, .good, .forced: .good
    case .book: .book
    case .inaccuracy: .inaccuracy
    case .mistake: .mistake
    case .miss: .miss
    case .blunder: .blunder
    }
  }

  var color: Color { quality.color }
}

extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
