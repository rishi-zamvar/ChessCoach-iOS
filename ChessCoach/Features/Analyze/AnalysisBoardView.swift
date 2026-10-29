import ChessCoachKit
import ChessKit
import SwiftUI

/// What to open on the analysis board.
struct AnalysisRequest: Identifiable {
  let id = UUID()
  var startFEN: String
  var moves: [String] = []
  var flipped = false
  var title = "Analysis"
}

/// Start the analysis board from the opening position or a pasted FEN / PGN.
struct PastePositionSheet: View {
  let onOpen: (AnalysisRequest) -> Void
  @State private var text = ""
  @State private var error: String?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Spacing.l) {
        TextField("Paste a FEN or PGN (optional)", text: $text, axis: .vertical)
          .lineLimit(3...8)
          .font(Typography.mono)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .padding(Spacing.m)
          .background(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).fill(Palette.surfaceRaised))
          .overlay(RoundedRectangle(cornerRadius: Spacing.cornerMedium, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.75))
          .accessibilityIdentifier("paste-position")
        if let error { Text(error).font(Typography.caption).foregroundStyle(Palette.danger) }
        PrimaryButton(title: text.isEmpty ? "Start from the opening" : "Open position", action: open, icon: "magnifyingglass")
          .accessibilityIdentifier("paste-open")
        Spacer()
      }
      .padding(Spacing.xl)
      .background(Palette.surfaceBase.ignoresSafeArea())
      .navigationTitle("Analysis board")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private func open() {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if input.isEmpty { return onOpen(AnalysisRequest(startFEN: GameSession.standardFEN)) }
    if Position(fen: input) != nil { return onOpen(AnalysisRequest(startFEN: input, flipped: input.contains(" b "))) }
    if let game = GameSession(pgn: input), !game.history.isEmpty || input.contains("[") {
      return onOpen(AnalysisRequest(startFEN: game.startFEN, moves: game.history.map(\.uci), title: "Analyze game"))
    }
    error = "That isn't a FEN or PGN this board can read. Check it and try again."
  }
}

/// The analysis board (spec W4): try any move for either side, see the engine's eval and top lines,
/// "explain this move", undo/redo, flip, reset, copy FEN/PGN, and optionally have the engine answer.
struct AnalysisBoardView: View {
  let request: AnalysisRequest

  enum Opponent: String, CaseIterable, Identifiable {
    case off, maia, stockfish
    var id: String { rawValue }
    var title: String {
      switch self {
      case .off: "Off"
      case .maia: "Maia 1100"
      case .stockfish: "Stockfish"
      }
    }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(AppEnvironment.self) private var env
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue
  @AppStorage(BoardSettings.coordinatesKey) private var showCoordinates = true
  @State private var line: AnalysisLine
  @State private var flipped: Bool
  @State private var interaction = BoardInteraction()
  @State private var lines: [EngineLine] = []
  @State private var thinking = false
  @State private var opponent: Opponent = .off
  @State private var showExplanation = true
  @State private var copied: String?

  init(request: AnalysisRequest) {
    self.request = request
    _line = State(initialValue: AnalysisLine(startFEN: request.startFEN, moves: request.moves))
    _flipped = State(initialValue: request.flipped)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      HStack(spacing: Spacing.s) {
        EvalBar(whiteWin: whiteWin, flipped: flipped)
          .frame(width: 14)
          .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        BoardView(
          position: line.session.position,
          highlights: BoardHighlights.make(session: line.session, ply: line.cursor, interaction: interaction),
          annotations: bestArrow,
          theme: BoardTheme.named(themeID),
          pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
          flipped: flipped,
          showCoordinates: showCoordinates,
          interactive: !thinking || opponent == .off,
          onTap: tap,
          onDragBegan: { interaction.dragBegan(at: $0, session: line.session, userColor: line.session.sideToMove) },
          onDragEnded: { square in
            if case .move(let from, let to) = interaction.dragEnded(at: square, session: line.session, userColor: line.session.sideToMove) {
              play(from: from, to: to)
            }
          },
          onDragCancelled: { interaction.dragCancelled() }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .padding(.horizontal, Spacing.m)
      .padding(.top, Spacing.s)

      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.m) {
          explanation
          engineLines
          Picker("Engine replies", selection: $opponent) {
            ForEach(Opponent.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("analysis-opponent")
          Text(opponent == .off ? "Move either side. The engine shows its best lines." : "Play from here: \(opponent.title) answers your moves.")
            .font(Typography.caption).foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.m)
      }
      controls
    }
    .background(Palette.surfaceBase.ignoresSafeArea())
    .screen("analysis", context: ["fen": .string(line.fen), "ply": .int(line.cursor)], board: true)
    .task(id: line.fen) { await analyse() }
  }

  // MARK: - Pieces

  private var header: some View {
    HStack {
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(Typography.body.weight(.semibold)).frame(width: 44, height: 44)
      }
      .accessibilityLabel("Close")
      .accessibilityIdentifier("analysis-close")
      Spacer()
      Text(request.title).font(Typography.bodyEmph).foregroundStyle(Palette.textPrimary)
      Spacer()
      FeedbackButton()
      Menu {
        Button("Copy FEN") { copy(line.fen, "FEN") }
        Button("Copy PGN") { copy(line.pgn, "PGN") }
      } label: {
        Image(systemName: "square.on.square").font(Typography.body.weight(.semibold)).frame(width: 44, height: 44)
      }
      .accessibilityLabel("Copy position")
    }
    .foregroundStyle(Palette.textSecondary)
    .padding(.horizontal, Spacing.s)
    .background(Palette.surfaceRaised)
  }

  /// What the last move did, in a plain sentence (offline, from engine-checked facts).
  @ViewBuilder private var explanation: some View {
    if let copied {
      Label("\(copied) copied", systemImage: "checkmark").font(Typography.callout).foregroundStyle(Palette.success)
    } else if showExplanation, line.cursor > 0, let last = line.lastMove {
      let before = AnalysisLine(startFEN: line.startFEN, moves: line.moves, cursor: line.cursor - 1).fen
      VStack(alignment: .leading, spacing: 4) {
        Eyebrow(text: "This move")
        Text(Explainer.reason(fen: before, uci: last) ?? (line.san.last ?? ""))
          .font(Typography.coachSpeech).foregroundStyle(Palette.textPrimary)
          .accessibilityIdentifier("analysis-explain")
      }
    } else {
      Text("Make a move to see what it does.").font(Typography.callout).foregroundStyle(Palette.textSecondary)
    }
  }

  private var engineLines: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Eyebrow(text: "Engine lines")
        if thinking { ProgressView().controlSize(.mini) }
      }
      if lines.isEmpty && !thinking {
        Text(env.engineHost == nil ? "The engine isn't available on this device." : "No moves here.")
          .font(Typography.caption).foregroundStyle(Palette.textSecondary)
      }
      ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, l in
        Button { if let first = l.pv.first { play(uci: first) } } label: {
          HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(scoreText(l.score)).font(Typography.mono.weight(.semibold)).foregroundStyle(Palette.textPrimary)
              .frame(width: 56, alignment: .leading)
            Text(FactExtractor.sanLine(fen: line.fen, ucis: Array(l.pv.prefix(6))).joined(separator: " "))
              .font(Typography.mono).foregroundStyle(Palette.textSecondary).lineLimit(1)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 6)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Play this line's first move")
      }
    }
    .accessibilityIdentifier("analysis-lines")
  }

  private var controls: some View {
    HStack(spacing: Spacing.s) {
      ActionButton(title: "", systemImage: "backward.end", label: "Back to start") { line.reset() }
      ActionButton(title: "", systemImage: "chevron.left", label: "Undo") { line.undo() }
        .disabled(!line.canUndo)
        .accessibilityIdentifier("analysis-undo")
      ActionButton(title: "", systemImage: "chevron.right", label: "Redo") { line.redo() }
        .disabled(!line.canRedo)
      ActionButton(title: "", systemImage: "arrow.up.arrow.down", label: "Flip board") { flipped.toggle() }
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .glassCapsule()
    .padding(.horizontal, Spacing.m)
    .padding(.bottom, Spacing.s)
  }

  // MARK: - Moves + engine

  private func tap(_ square: Square) {
    if case .move(let from, let to) = interaction.tap(square, session: line.session, userColor: line.session.sideToMove) {
      play(from: from, to: to)
    }
  }

  private func play(from: Square, to: Square) {
    var s = line.session
    let promo: Piece.Kind? = s.isPromotion(from: from, to: to) ? .queen : nil
    guard case .applied(let played) = s.apply(from: from, to: to, promotion: promo) else { return }
    play(uci: played.uci)
  }

  private func play(uci: String) {
    guard line.play(uci: uci) else { return }
    interaction.reset()
    copied = nil
    if let last = line.session.lastMove { env.sounds.play(SoundEvent.forMove(last, gameOver: line.session.isOver)) }
    env.telemetry.event("analysis.move", metadata: ["ply": .int(line.cursor)])
    if opponent != .off { Task { await reply() } }
  }

  /// "Play from here": the chosen engine answers.
  private func reply() async {
    guard !line.session.isOver, let host = env.engineHost else { return }
    let fen = line.fen
    let kind: EngineKind = opponent == .maia ? .maia(rating: 1100) : .stockfish
    let limit: SearchLimit = opponent == .maia ? .nodes(1) : .depthOrTime(depth: 14, milliseconds: 600)
    guard let result = try? await host.search(kind, fen: fen, limit: limit), line.fen == fen else { return }
    try? await Task.sleep(for: .milliseconds(350))
    if line.fen == fen, line.play(uci: result.bestMove), let last = line.session.lastMove {
      env.sounds.play(SoundEvent.forMove(last, gameOver: line.session.isOver))
    }
  }

  private func analyse() async {
    guard let host = env.engineHost, !line.session.isOver else {
      lines = []
      return
    }
    thinking = true
    defer { thinking = false }
    let fen = line.fen
    guard let result = try? await host.search(.stockfish, fen: fen, limit: .depthOrTime(depth: 16, milliseconds: 900), multipv: 3),
      line.fen == fen
    else { return }
    lines = result.lines
  }

  private var bestArrow: AnnotationLayer {
    var layer = AnnotationLayer()
    if let best = lines.first?.pv.first.flatMap(UCIMove.init) {
      layer.arrows = [Arrow(from: best.from, to: best.to, color: .blue)]
    }
    return layer
  }

  /// White's winning chance for the eval bar.
  private var whiteWin: Double {
    guard let score = lines.first?.score else { return 50 }
    let mover = WinChance.winPercent(score)
    return line.session.sideToMove == .white ? mover : 100 - mover
  }

  /// Score from White's side, e.g. "+1.2", "M3".
  private func scoreText(_ score: EngineScore) -> String {
    let sign = line.session.sideToMove == .white ? 1 : -1
    switch score {
    case .centipawns(let cp): return String(format: "%+.1f", Double(cp * sign) / 100)
    case .mate(let n): return "M\(n * sign)"
    }
  }

  private func copy(_ text: String, _ what: String) {
    UIPasteboard.general.string = text
    copied = what
    Haptics.success()
  }
}
