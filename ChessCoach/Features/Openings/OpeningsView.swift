import ChessCoachKit
import ChessKit
import SwiftUI

/// Openings: the learner's style repertoires (Learn / Drill), and other styles to browse.
struct OpeningsView: View {
  @Environment(TrainingService.self) private var training
  @State private var session: OpeningSession?

  struct OpeningSession: Identifiable {
    let id = UUID()
    let repertoire: Repertoire
    let mode: OpeningTrainerView.Mode
  }

  private var style: String { training.profile?.style.rawValue ?? "allRounder" }
  private var mine: [Repertoire] { RepertoireLibrary.forStyle(style) }

  var body: some View {
    ZStack {
      BackgroundAtmosphere().ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Eyebrow(text: "Openings · \(training.profile?.style.title ?? "All-rounder")")
          Text("Your repertoire").font(Typography.display).foregroundStyle(Palette.ink)
          Text("Learn the idea behind every move, then drill it until it's automatic. Traps are marked — set them, and never fall for them.")
            .font(Typography.callout).foregroundStyle(Palette.textSecondary)
          if mine.isEmpty {
            EmptyState(title: "No repertoire yet", message: "Repertoires for your style are on their way.", systemImage: "book.closed")
          }
          ForEach(mine) { rep in
            RepertoireCard(repertoire: rep) { session = OpeningSession(repertoire: rep, mode: .learn) } drill: {
              session = OpeningSession(repertoire: rep, mode: .drill)
            }
          }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, 80)
      }
    }
    .fullScreenCover(item: $session, onDismiss: { training.refresh() }) { s in
      OpeningTrainerView(repertoire: s.repertoire, mode: s.mode)
    }
  }
}

private struct RepertoireCard: View {
  let repertoire: Repertoire
  let learn: () -> Void
  let drill: () -> Void

  var body: some View {
    Card {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Eyebrow(text: repertoire.side == .white ? "As White" : repertoire.fileName.hasSuffix("d4") ? "As Black vs 1.d4" : "As Black vs 1.e4")
          Text(repertoire.name).font(Typography.titleSmall).foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
          if !repertoire.summary.isEmpty {
            Text(repertoire.summary).font(Typography.callout).foregroundStyle(Palette.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Text("\(repertoire.lines.count) lines · \(repertoire.trapCount) traps")
            .font(Typography.caption).foregroundStyle(Palette.textMuted).padding(.top, 2)
        }
        Spacer()
      }
      HStack(spacing: Spacing.s) {
        SecondaryButton(title: "Learn", action: learn)
        PrimaryButton(title: "Drill", action: drill, icon: "bolt.fill")
      }
      .padding(.top, Spacing.m)
    }
    .accessibilityIdentifier("repertoire-\(repertoire.fileName)")
  }
}

/// Learn: walk each line with ideas and arrows (you play your own moves).
/// Drill: the opponent picks branches; you must find your repertoire move.
struct OpeningTrainerView: View {
  enum Mode { case learn, drill }

  let repertoire: Repertoire
  let mode: Mode

  @Environment(\.dismiss) private var dismiss
  @Environment(TrainingService.self) private var training
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue

  @State private var lineIndex = 0
  @State private var cursor: Int?  // last played node
  @State private var game = GameSession()
  @State private var interaction = BoardInteraction()
  @State private var message = ""
  @State private var wrong: String?
  @State private var showAnswer = false
  @State private var correct = 0
  @State private var misses = 0
  @State private var finishedLine = false
  @State private var askingCoach = false
  @State private var coachArrows: [Arrow] = []
  /// The opponent's reply, held until you tap so you can read why your move was played.
  @State private var pendingReply: RepertoireNode?

  var body: some View {
    VStack(spacing: 0) {
      header
      coach
      BoardView(
        position: game.position,
        highlights: BoardHighlights.make(session: game, ply: game.history.count, interaction: interaction),
        annotations: annotations,
        theme: BoardTheme.named(themeID),
        pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
        flipped: repertoire.side == .black,
        interactive: isUserTurn && !finishedLine,
        onTap: tap,
        onDragBegan: { interaction.dragBegan(at: $0, session: game, userColor: repertoire.side) },
        onDragEnded: { square in
          if case .move(let from, let to) = interaction.dragEnded(at: square, session: game, userColor: repertoire.side) {
            attempt(from: from, to: to)
          }
        },
        onDragCancelled: { interaction.dragCancelled() })
      .overlay {
        if pendingReply != nil {
          Color.clear.contentShape(Rectangle()).onTapGesture(perform: showReply)
            .accessibilityIdentifier("opening-board-continue")
        }
      }
      Spacer(minLength: 0)
      controls
    }
    .background(ChessChrome.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
    .onAppear { startLine() }
    .onChange(of: game.history.count) { _, _ in coachArrows = [] }
    .sheet(isPresented: $askingCoach) {
      AskCoachSheet(
        fen: game.position.fen, history: game.history.map(\.san),
        suggestions: ["Why is this move good?", "What if they play something else?", "What's the trap here?"]
      ) { coachArrows = $0 }
      .presentationDetents([.medium, .large])
    }
  }

  // MARK: - UI

  private var header: some View {
    HStack {
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
      }
      Spacer()
      VStack(spacing: 2) {
        Text(repertoire.name).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
        Text(mode == .learn ? "Learn · line \(lineIndex + 1) of \(repertoire.lines.count)" : "Drill · \(correct) right · \(misses) missed")
          .font(.system(size: 12, design: .rounded))
      }
      Spacer()
      Color.clear.frame(width: 44, height: 44)
    }
    .foregroundStyle(ChessChrome.textSecondary)
    .background(ChessChrome.bar)
  }

  private var coach: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      Text("♞").font(.system(size: 22, design: .serif)).foregroundStyle(ChessChrome.accentGreen)
        .frame(width: 36, height: 36).background(Circle().fill(ChessChrome.card))
      VStack(alignment: .leading, spacing: 4) {
        if let node = cursor.map(repertoire.node), let trap = node.trap {
          Label("Trap: \(trap)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(MoveClass.mistake.color)
        }
        if let node = cursor.map(repertoire.node), node.isDeviation {
          Label("A common deviation at your level", systemImage: "arrow.triangle.branch")
            .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(MoveClass.great.color)
        }
        Text((wrong.map { "\($0) isn't in your repertoire. " } ?? "") + message)
          .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(ChessChrome.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("opening-coach")
        if pendingReply != nil {
          Text("Tap the board when you're ready for their reply.")
            .font(.system(size: 12, design: .rounded)).foregroundStyle(ChessChrome.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.m)
      .background(RoundedRectangle(cornerRadius: 12).fill(ChessChrome.card))
    }
    .padding(Spacing.m)
    .frame(minHeight: 110, alignment: .top)
  }

  private var controls: some View {
    HStack(spacing: Spacing.s) {
      if pendingReply != nil {
        PuzzleButton(title: "Their move", systemImage: "arrow.right", prominent: true, action: showReply)
          .accessibilityIdentifier("opening-continue")
      } else if finishedLine {
        PuzzleButton(title: mode == .learn && lineIndex + 1 < repertoire.lines.count ? "Next line" : "Again", systemImage: "arrow.right", prominent: true) {
          if mode == .learn { lineIndex = (lineIndex + 1) % max(1, repertoire.lines.count) }
          startLine()
        }
      } else if isUserTurn {
        PuzzleButton(title: showAnswer ? "Hide" : "Show move", systemImage: "eye") { showAnswer.toggle() }
      }
      if env.server.hasKey {
        PuzzleButton(title: "Ask", systemImage: "bubble.left.and.text.bubble.right") { askingCoach = true }
          .frame(maxWidth: 110)
      }
    }
    .padding(Spacing.m)
    .background(ChessChrome.bar)
  }

  private var annotations: AnnotationLayer {
    var layer = AnnotationLayer()
    if let node = cursor.map(repertoire.node) {
      layer.arrows = node.arrows
      layer.circles = node.highlights
    }
    layer.arrows += coachArrows
    if isUserTurn, mode == .learn || showAnswer {
      for option in options where mode == .drill || option.id == learnTarget?.id {
        if let m = UCIMove(option.uci) { layer.arrows.append(Arrow(from: m.from, to: m.to, color: .blue)) }
      }
    }
    return layer
  }

  // MARK: - Flow

  private var options: [RepertoireNode] { repertoire.children(of: cursor) }
  private var isUserTurn: Bool { !options.isEmpty && game.sideToMove == repertoire.side }

  /// In Learn mode, the move this line expects next.
  private var learnTarget: RepertoireNode? {
    guard mode == .learn, lineIndex < repertoire.lines.count else { return nil }
    let line = repertoire.lines[lineIndex]
    return game.history.count < line.count ? line[game.history.count] : nil
  }

  private func startLine() {
    game = GameSession(startFEN: repertoire.startFEN)
    cursor = nil
    wrong = nil
    showAnswer = false
    finishedLine = false
    pendingReply = nil
    interaction.reset()
    message = mode == .learn ? "Play the blue arrow. I'll explain each move." : "Play your repertoire. I'll play the replies you'll meet."
    advanceOpponent()
  }

  private func tap(_ square: Square) {
    if case .move(let from, let to) = interaction.tap(square, session: game, userColor: repertoire.side) {
      attempt(from: from, to: to)
    }
  }

  private func attempt(from: Square, to: Square) {
    var trial = game
    guard case .applied(let played) = trial.apply(from: from, to: to, promotion: trial.isPromotion(from: from, to: to) ? .queen : nil) else { return }
    let accepted = mode == .learn ? [learnTarget].compactMap { $0 } : options
    if let node = accepted.first(where: { $0.uci == played.uci }) {
      wrong = nil
      showAnswer = false
      if mode == .drill { correct += 1 }
      play(node)
      advanceOpponent(waitForTap: true)
    } else {
      wrong = played.san
      env.sounds.play(.illegal)
      if mode == .drill {
        misses += 1
        if let expected = options.first {
          training.addOpeningReview(repertoire: repertoire, node: expected)
        }
      }
    }
  }

  private func play(_ node: RepertoireNode) {
    if case .applied(let played) = game.apply(uci: node.uci) {
      env.sounds.play(SoundEvent.forMove(played, gameOver: game.isOver))
    }
    cursor = node.id
    message = node.idea.isEmpty ? node.san : "\(node.san): \(node.idea)"
    if options.isEmpty { endLine() }
  }

  private func advanceOpponent(waitForTap: Bool = false) {
    guard !options.isEmpty, game.sideToMove != repertoire.side else { return }
    let next: RepertoireNode?
    if mode == .learn {
      next = learnTarget
    } else {
      // Main line half the time, the rest spread over deviations.
      let opts = options
      next = opts.count == 1 || Double.random(in: 0..<1) < 0.5 ? opts.first : opts.dropFirst().randomElement()
    }
    guard let next else { return endLine() }
    if waitForTap { return pendingReply = next }
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      play(next)
    }
  }

  private func showReply() {
    guard let next = pendingReply else { return }
    pendingReply = nil
    Haptics.light()
    play(next)
  }

  private func endLine() {
    finishedLine = true
    env.telemetry.event("opening.line", metadata: ["rep": .string(repertoire.fileName), "mode": .string(mode == .learn ? "learn" : "drill"), "misses": .int(misses)])
  }
}
