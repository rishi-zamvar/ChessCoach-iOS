import ChessCoachKit
import ChessKit
import SwiftUI

/// Openings: the learner's style repertoires plus any they added (Learn / Drill); + adds more,
/// each rated for how it fits their style.
struct OpeningsView: View {
  @Environment(TrainingService.self) private var training
  @State private var session: OpeningSession?
  @State private var adding = false
  @AppStorage(AppEnvironment.addedOpeningsKey) private var addedRaw = ""

  struct OpeningSession: Identifiable {
    let id = UUID()
    let repertoire: Repertoire
    let mode: OpeningTrainerView.Mode
  }

  private var style: String { training.profile?.style.rawValue ?? "allRounder" }
  private var added: [String] { addedRaw.split(separator: ",").map(String.init) }
  private var mine: [Repertoire] { RepertoireLibrary.mine(style: style, added: added) }

  var body: some View {
    ZStack {
      BackgroundAtmosphere().ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          HStack {
            Eyebrow(text: "Openings · \(training.profile?.style.title ?? "All-rounder")")
            Spacer()
            Button { adding = true } label: {
              Image(systemName: "plus").font(Typography.symbol(18, weight: .semibold)).foregroundStyle(Palette.primaryDeep)
                .frame(width: 40, height: 40).background(Circle().fill(Palette.paper))
            }
            .accessibilityLabel("Add openings")
            .accessibilityIdentifier("openings-add")
          }
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
            .contextMenu {
              if added.contains(rep.fileName) {
                Button("Remove from repertoire", role: .destructive) { addedRaw = added.filter { $0 != rep.fileName }.joined(separator: ",") }
              }
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
    .sheet(isPresented: $adding) {
      AddOpeningsSheet(
        style: style, quizScore: training.profile?.quizScore ?? 0, have: Set(mine.map(\.fileName))
      ) { addedRaw = (added + [$0]).joined(separator: ",") }
      .presentationDetents([.large])
    }
  }
}

/// Every opening not yet in your repertoire, best fit first, each with a fit rating.
private struct AddOpeningsSheet: View {
  let style: String
  let quizScore: Double
  let have: Set<String>
  let add: (String) -> Void
  @Environment(\.dismiss) private var dismiss

  private var candidates: [Repertoire] {
    RepertoireLibrary.all().filter { !have.contains($0.fileName) }
      .sorted { OpeningFit.stars($0, style: style, quizScore: quizScore) > OpeningFit.stars($1, style: style, quizScore: quizScore) }
  }

  var body: some View {
    NavigationStack {
      List {
        if candidates.isEmpty {
          Text("You already have every opening.").foregroundStyle(Palette.textSecondary)
        }
        ForEach(candidates) { rep in
          let stars = OpeningFit.stars(rep, style: style, quizScore: quizScore)
          HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
              Eyebrow(text: RepertoireCard.sideLabel(rep))
              Text(rep.name).font(Typography.titleSmall).foregroundStyle(Palette.ink)
              if !rep.summary.isEmpty {
                Text(rep.summary).font(Typography.caption).foregroundStyle(Palette.textSecondary)
              }
              HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                  Image(systemName: i < stars ? "star.fill" : "star").font(Typography.symbol(11))
                    .foregroundStyle(i < stars ? Palette.accentDeep : Palette.textMuted)
                }
                Text("Style fit").font(Typography.caption).foregroundStyle(Palette.textMuted).padding(.leading, 4)
              }
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("Style fit \(stars) of 5")
              .accessibilityIdentifier("fit-\(rep.fileName)")
              Text(OpeningFit.reason(rep, style: style, quizScore: quizScore))
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            Button("Add") {
              Haptics.selection()
              add(rep.fileName)
            }
            .buttonStyle(.borderedProminent).tint(Palette.primaryDeep)
            .accessibilityIdentifier("add-\(rep.fileName)")
          }
          .padding(.vertical, 4)
        }
      }
      .navigationTitle("Add openings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}

private struct RepertoireCard: View {
  let repertoire: Repertoire
  let learn: () -> Void
  let drill: () -> Void

  static func sideLabel(_ r: Repertoire) -> String {
    r.side == .white ? "As White" : r.fileName.hasSuffix("d4") ? "As Black vs 1.d4" : "As Black vs 1.e4"
  }

  var body: some View {
    Card {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Eyebrow(text: Self.sideLabel(repertoire))
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
  /// Learn: replaying the line just learned, from memory (no arrows), to lock it in.
  @State private var recall = false
  @State private var recallMisses = 0
  /// Learn: clean, fast from-memory runs of this line in a row (3 unlock the next line).
  @State private var mastery = LineMastery()
  /// When it became your turn (from-memory timing) and the slowest move so far this run.
  @State private var turnStart: Date?
  @State private var slowest: Double = 0
  /// Lines you've locked in, as "<repertoire>#<line>", kept across sessions.
  @AppStorage("openings.mastered") private var masteredRaw = ""

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
    .background(Palette.surfaceBase.ignoresSafeArea())
    .onAppear {
      // Pick up at the first line you haven't locked in yet.
      if mode == .learn { lineIndex = repertoire.lines.indices.first { !isMastered($0) } ?? 0 }
      startLine()
    }
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
        Image(systemName: "xmark").font(Typography.symbol(16, weight: .semibold)).frame(width: 44, height: 44)
      }
      Spacer()
      VStack(spacing: 2) {
        Text(repertoire.name).font(.system(.subheadline).weight(.bold)).lineLimit(1)
        Text(mode == .learn ? "Learn · line \(lineIndex + 1) of \(repertoire.lines.count)\(recall ? " · from memory \(mastery.streak)/\(LineMastery.required)" : "")" : "Drill · \(correct) right · \(misses) missed")
          .font(.system(.caption))
      }
      Spacer()
      if mode == .learn {
        // Jump to the mainline or any line, any time.
        Menu {
          ForEach(Array(repertoire.lines.enumerated()), id: \.offset) { i, line in
            Button {
              select(line: i)
            } label: {
              Label(
                "\(i == 0 ? "Mainline" : "Line \(i + 1)"): \(line.prefix(6).map(\.san).joined(separator: " "))",
                systemImage: isMastered(i) ? "checkmark.circle.fill" : (i == lineIndex ? "circle.inset.filled" : "circle"))
            }
          }
        } label: {
          Image(systemName: "list.bullet").font(Typography.symbol(16, weight: .semibold)).frame(width: 44, height: 44)
        }
        .accessibilityIdentifier("opening-lines")
      } else {
        Color.clear.frame(width: 44, height: 44)
      }
    }
    .foregroundStyle(Palette.textSecondary)
    .background(Palette.surfaceRaised)
  }

  private var coach: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      Text("♞").font(Typography.symbol(22, design: .serif)).foregroundStyle(Palette.sage)
        .frame(width: 36, height: 36).background(Circle().fill(Palette.surfaceRaised))
      VStack(alignment: .leading, spacing: 4) {
        if let node = cursor.map(repertoire.node), let trap = node.trap {
          Label("Trap: \(trap)", systemImage: "exclamationmark.triangle.fill")
            .font(.system(.footnote).weight(.bold)).foregroundStyle(MoveClass.mistake.color)
        }
        if let node = cursor.map(repertoire.node), node.isDeviation {
          Label("A common deviation at your level", systemImage: "arrow.triangle.branch")
            .font(.system(.footnote).weight(.bold)).foregroundStyle(MoveClass.great.color)
        }
        Text((wrong.map { "\($0) isn't in your repertoire. " } ?? "") + message)
          .font(.system(.subheadline).weight(.medium)).foregroundStyle(Palette.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("opening-coach")
        if pendingReply != nil {
          Text("Tap the board when you're ready for their reply.")
            .font(.system(.caption)).foregroundStyle(Palette.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.m)
      .background(RoundedRectangle(cornerRadius: Spacing.cornerMedium).fill(Palette.surfaceRaised))
    }
    .padding(Spacing.m)
    .frame(minHeight: 110, alignment: .top)
  }

  private var controls: some View {
    HStack(spacing: Spacing.s) {
      if pendingReply != nil {
        ActionButton(title: "Their move", systemImage: "arrow.right", prominent: true, action: showReply)
          .accessibilityIdentifier("opening-continue")
      } else if finishedLine, mode == .learn {
        let unlocked = isMastered(lineIndex)
        ActionButton(title: "", systemImage: "arrow.triangle.branch") { startLine() }
          .frame(maxWidth: 56)
          .accessibilityIdentifier("opening-arrows-again")
        ActionButton(title: "From memory", systemImage: "brain.head.profile", prominent: !unlocked) { startLine(recall: true) }
          .accessibilityIdentifier("opening-repeat")
        ActionButton(
          title: lineIndex + 1 < repertoire.lines.count ? (unlocked ? "Next line" : "Next \(mastery.streak)/\(LineMastery.required)") : "Start over",
          systemImage: unlocked ? "arrow.right" : "lock.fill", prominent: unlocked
        ) {
          select(line: (lineIndex + 1) % max(1, repertoire.lines.count))
        }
        .disabled(!unlocked)
        .accessibilityIdentifier("opening-next")
      } else if finishedLine {
        ActionButton(title: "Again", systemImage: "arrow.right", prominent: true) { startLine() }
          .accessibilityIdentifier("opening-next")
      } else if isUserTurn {
        ActionButton(title: showAnswer ? "Hide" : "Show move", systemImage: "eye") { showAnswer.toggle() }
      }
      if env.aiSettings.hasKey {
        ActionButton(title: "Ask", systemImage: "bubble.left.and.text.bubble.right") { askingCoach = true }
          .frame(maxWidth: 110)
      }
    }
    .padding(Spacing.m)
    .background(Palette.surfaceRaised)
  }

  private var annotations: AnnotationLayer {
    var layer = AnnotationLayer()
    if let node = cursor.map(repertoire.node) {
      layer.arrows = node.arrows
      layer.circles = node.highlights
    }
    layer.arrows += coachArrows
    if isUserTurn, (mode == .learn && !recall) || showAnswer {
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

  private func startLine(recall: Bool = false) {
    self.recall = recall
    recallMisses = 0
    slowest = 0
    turnStart = nil
    game = GameSession(startFEN: repertoire.startFEN)
    cursor = nil
    wrong = nil
    showAnswer = false
    finishedLine = false
    pendingReply = nil
    interaction.reset()
    message =
      recall ? "Now play the same line from memory. No arrows this time."
      : mode == .learn ? "Play the blue arrow. I'll explain each move." : "Play your repertoire. I'll play the replies you'll meet."
    advanceOpponent()
    if isUserTurn { turnStart = Date() }
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
      if recall, let started = turnStart { slowest = max(slowest, Date().timeIntervalSince(started)) }
      play(node)
      // From memory it's a timed run, so their reply comes straight away.
      advanceOpponent(waitForTap: !recall)
    } else {
      wrong = played.san
      env.sounds.play(.illegal)
      if mode == .drill {
        misses += 1
        if let expected = options.first {
          training.addOpeningReview(repertoire: repertoire, node: expected)
        }
      } else if recall, let expected = learnTarget {
        // Forgot it: it comes back in your reviews too.
        recallMisses += 1
        training.addOpeningReview(repertoire: repertoire, node: expected)
      }
    }
  }

  private func play(_ node: RepertoireNode) {
    if case .applied(let played) = game.apply(uci: node.uci) {
      env.sounds.play(SoundEvent.forMove(played, gameOver: game.isOver))
    }
    cursor = node.id
    message = node.idea.isEmpty ? node.san : "\(node.san): \(node.idea)"
    if isUserTurn { turnStart = Date() }
    if options.isEmpty { endLine() }
  }

  private func masteryKey(_ line: Int) -> String { "\(repertoire.fileName)#\(line)" }
  private func isMastered(_ line: Int) -> Bool { masteredRaw.split(separator: ",").contains { $0 == masteryKey(line) } }

  /// Switches to a line (fresh streak) and plays it with arrows.
  private func select(line: Int) {
    lineIndex = line
    mastery = LineMastery()
    startLine()
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
    if mode == .learn, recall {
      let counted = mastery.record(slips: recallMisses, slowestMove: slowest)
      if mastery.isMastered, !isMastered(lineIndex) {
        masteredRaw = (masteredRaw.split(separator: ",").map(String.init) + [masteryKey(lineIndex)]).joined(separator: ",")
      }
      let need = LineMastery.required
      message +=
        mastery.isMastered ? "\n\nLocked in: \(need) fast runs from memory. On to the next line, or keep repeating."
        : counted ? "\n\nClean and fast: \(mastery.streak)/\(need). Again from memory."
        : recallMisses > 0 ? "\n\n\(recallMisses) slip\(recallMisses == 1 ? "" : "s"): back to 0/\(need)."
        : "\n\nClean, but one move took \(Int(slowest.rounded())) seconds. Every move under \(Int(LineMastery.fastSeconds)) seconds to count: 0/\(need)."
    } else if mode == .learn {
      message += "\n\nNow play it from memory, \(LineMastery.required) times fast, to unlock the next line."
    }
    env.telemetry.event("opening.line", metadata: ["rep": .string(repertoire.fileName), "mode": .string(mode == .learn ? (recall ? "recall" : "learn") : "drill"),
      "misses": .int(mode == .drill ? misses : recallMisses)])
  }
}
