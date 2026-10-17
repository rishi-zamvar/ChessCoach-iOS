import ChessCoachKit
import ChessKit
import SwiftUI

/// chess.com-style game screen: move strip, opponent bar, board, player bar, toolbar.
struct GameScreen: View {
  @Bindable var game: GameController
  var onClose: () -> Void

  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue
  @AppStorage(BoardSettings.coordinatesKey) private var showCoordinates = true
  @State private var showOptions = false
  @State private var confirmResign = false
  @State private var drawDeclined = false
  @State private var resultDismissed = false
  @State private var reviewGame: GameRecord?
  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis

  private var theme: BoardTheme { BoardTheme.named(themeID) }
  private var pieceSet: PieceSetID { PieceSetID(rawValue: pieceSetRaw) ?? .default }
  private var topColor: Piece.Color { game.flipped ? .white : .black }
  private var bottomColor: Piece.Color { topColor.opposite }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { context in
      VStack(spacing: 0) {
        header
        MoveStrip(history: game.session.history, currentPly: game.viewPly) { game.jump(toPly: $0) }
        if let focus = game.focus {
          HStack(spacing: Spacing.xs) {
            chip(stageTitle, systemImage: stageIcon, tint: ChessChrome.textSecondary).accessibilityIdentifier("coach-stage")
            chip(focus.title, systemImage: "scope", tint: ChessChrome.accentGreen).accessibilityIdentifier("coach-focus")
          }
          .lineLimit(1)
          .padding(.horizontal, Spacing.m)
          .padding(.top, Spacing.xs)
        }
        // Everything that changes per move lives in this scroll area, so the board never shifts.
        // Capped so the board keeps the full width: long coach text scrolls instead.
        ScrollView {
          VStack(spacing: 0) {
            moveCaption
            coachMessage
          }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: 56, maxHeight: 112)
        PlayerBar(
          name: name(for: topColor), rating: rating(for: topColor), color: topColor,
          captured: game.session.captured(by: topColor), advantage: advantage(for: topColor),
          clock: clockText(topColor), clockActive: clockActive(topColor), lowTime: game.isLowTime(topColor),
          thinking: game.phase == .botThinking && topColor != game.userColor, pieceSet: pieceSet)
        board
          .layoutPriority(1)
        PlayerBar(
          name: name(for: bottomColor), rating: rating(for: bottomColor), color: bottomColor,
          captured: game.session.captured(by: bottomColor), advantage: advantage(for: bottomColor),
          clock: clockText(bottomColor), clockActive: clockActive(bottomColor), lowTime: game.isLowTime(bottomColor),
          thinking: game.phase == .botThinking && bottomColor != game.userColor, pieceSet: pieceSet)
        Spacer(minLength: 0)
        toolbar
      }
      .onChange(of: context.date) { _, _ in game.tick() }
    }
    .background(ChessChrome.background.ignoresSafeArea())
    .overlay(alignment: .bottom) {
      if let pause = game.coachPause {
        CoachPauseCard(pause: pause, onTakeBack: game.takeBack, onShow: game.showBetterMove, onContinue: game.continueGame)
          .padding(Spacing.m)
          .padding(.bottom, 60)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: game.coachPause)
    .overlay {
      if let result = game.result, !resultDismissed {
        ResultCard(
          result: result, userColor: game.userColor, opponentName: game.bot.name,
          onReview: { reviewGame = try? env.gameStore.game(id: game.gameID.uuidString) },
          onNewGame: onClose, onDone: { resultDismissed = true })
        .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: game.isOver)
    .onAppear {
      analysis.beginForegroundEngineUse()
      game.start()
    }
    .onDisappear {
      analysis.endForegroundEngineUse()
      CoachSpeaker.shared.stop()
    }
    .onChange(of: game.coachLine?.id) { _, _ in
      guard let line = game.coachLine else { return }
      // Only the fixed headline is spoken (bundled Aman clips); the coach's own words show on screen.
      if let headline = line.headline, CoachMode.current == .voice { CoachSpeaker.shared.say(headline) }
      Haptics.soft()
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: game.coachLine?.id)
    .confirmationDialog("Resign this game?", isPresented: $confirmResign, titleVisibility: .visible) {
      Button("Resign", role: .destructive) { game.resign() }
        .accessibilityIdentifier("confirm-resign")
    }
    .alert("Draw declined", isPresented: $drawDeclined) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("\(game.bot.name) wants to play on.")
    }
    .fullScreenCover(item: $reviewGame) { record in
      ReviewScreen(game: record)
    }
    .sheet(isPresented: $showOptions) {
      BoardOptionsSheet(themeID: $themeID, pieceSetRaw: $pieceSetRaw, showCoordinates: $showCoordinates)
        .presentationDetents([.medium])
    }
  }

  // MARK: - Pieces

  /// What the move on the board does — yours and the bot's.
  @ViewBuilder
  private var moveCaption: some View {
    let history = game.session.history
    if game.viewPly > 0, game.viewPly <= history.count {
      let played = history[game.viewPly - 1]
      let who = played.color == game.userColor ? "You" : game.bot.name
      let isYou = played.color == game.userColor
      let why = isYou ? nil : game.botReasons[game.viewPly]
      let facts = Explainer.reason(fen: game.session.fen(atPly: game.viewPly - 1), uci: played.uci) ?? played.san
      MoveNote(who: who, isYou: isYou, san: played.san, text: why ?? facts, compact: true)
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.xs)
        .id(game.viewPly)
        .transition(.opacity)
        .accessibilityIdentifier("game-move-caption")
    }
  }

  /// Hint, coach line, nudge or "checking" — one at a time.
  @ViewBuilder
  private var coachMessage: some View {
    if let hint = game.hintText {
      CoachBanner(text: hint, systemImage: "lightbulb.fill", tint: MoveClass.great.color)
    } else if let line = game.coachLine {
      CoachLineBubble(
        headline: line.headline == line.text ? nil : line.headline, text: line.text, speaking: CoachSpeaker.shared.isSpeaking,
        onReplay: CoachMode.current == .voice ? line.headline.map { h in { CoachSpeaker.shared.say(h) } } : nil)
        .animation(.easeOut(duration: 0.2), value: line.text)
        .id(line.id)
        .transition(.move(edge: .top).combined(with: .opacity))
    } else if let nudge = game.nudge {
      CoachBanner(text: nudge, systemImage: "exclamationmark.bubble.fill", tint: MoveClass.inaccuracy.color)
    } else if game.phase == .coachChecking {
      CoachBanner(text: "Coach is looking at your move…", systemImage: "eye", tint: ChessChrome.textSecondary)
    }
  }

  private var stageTitle: String {
    switch game.stage {
    case .opening: game.openingName.map { "Opening · \($0)" } ?? "Opening"
    case .middlegame: "Middlegame"
    case .endgame: "Endgame"
    }
  }

  private var stageIcon: String {
    switch game.stage {
    case .opening: "book.closed"
    case .middlegame: "figure.fencing"
    case .endgame: "flag.checkered"
    }
  }

  private func chip(_ title: String, systemImage: String, tint: Color) -> some View {
    Label(title, systemImage: systemImage)
      .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(tint)
      .padding(.horizontal, 10).padding(.vertical, 4)
      .background(Capsule().fill(tint.opacity(0.15)))
  }

  private var coachTitle: String { game.isCoached ? "Play Coach" : (game.config.timeControl.isTimed ? game.config.timeControl.label : "Casual") }

  private var header: some View {
    HStack {
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .accessibilityIdentifier("game-close")
      Spacer()
      Text(coachTitle)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
      Spacer()
      Button { game.flip() } label: {
        Image(systemName: "arrow.up.arrow.down")
          .font(.system(size: 15, weight: .semibold))
          .frame(width: 44, height: 44)
      }
    }
    .foregroundStyle(ChessChrome.textSecondary)
    .padding(.horizontal, Spacing.s)
    .background(ChessChrome.bar)
  }

  private var board: some View {
    ZStack {
      BoardView(
        position: game.displayedPosition,
        highlights: game.highlights,
        annotations: game.annotations,
        theme: theme,
        pieceSet: pieceSet,
        flipped: game.flipped,
        showCoordinates: showCoordinates,
        interactive: !game.isOver,
        onTap: { game.tap($0) },
        onDragBegan: { game.dragBegan($0) },
        onDragEnded: { game.dragEnded(at: $0) },
        onDragCancelled: { game.dragCancelled() },
        onArrow: { game.annotations.toggleUserArrow(from: $0, to: $1) }
      )
      if let pending = game.pendingPromotion {
        PromotionPicker(
          square: pending.to, color: game.userColor, pieceSet: pieceSet, flipped: game.flipped,
          onPick: { game.choosePromotion($0) }, onCancel: { game.cancelPromotion() })
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var toolbar: some View {
    HStack(spacing: 0) {
      ToolbarButton(title: "Options", systemImage: "line.3.horizontal") { showOptions = true }
      if game.isCoached, !game.isOver {
        ToolbarButton(title: "Hint", systemImage: "lightbulb", enabled: game.phase == .userTurn) {
          Task { await game.hint() }
        }
        .accessibilityIdentifier("toolbar-hint")
      }
      if game.isOver {
        ToolbarButton(title: "New", systemImage: "plus") { onClose() }
      } else {
        ToolbarButton(title: "Draw", systemImage: "equal.circle") {
          if !game.offerDraw() { drawDeclined = true }
        }
        ToolbarButton(title: "Resign", systemImage: "flag") { confirmResign = true }
          .accessibilityIdentifier("toolbar-resign")
      }
      if !game.isOver {
        ToolbarButton(title: "Undo", systemImage: "arrow.uturn.backward", enabled: game.canUndo) {
          Haptics.medium()
          withAnimation(.easeOut(duration: 0.2)) { game.undoMove() }
        }
        .accessibilityIdentifier("toolbar-undo")
      }
      ToolbarButton(title: "Back", systemImage: "chevron.left", enabled: game.viewPly > 0) { game.stepBack() }
      ToolbarButton(title: "Forward", systemImage: "chevron.right", enabled: !game.isViewingLatest) { game.stepForward() }
    }
    .padding(.vertical, Spacing.xs)
    .background(ChessChrome.bar)
  }

  // MARK: - Helpers

  private func name(for color: Piece.Color) -> String {
    color == game.userColor ? "You" : game.bot.name
  }

  private func rating(for color: Piece.Color) -> Int? {
    color == game.userColor ? nil : game.bot.rating
  }

  private func advantage(for color: Piece.Color) -> Int {
    let balance = game.session.materialBalance * (color == .white ? 1 : -1)
    return max(0, balance)
  }

  private func clockActive(_ color: Piece.Color) -> Bool {
    game.clock.running == color
  }

  private func clockText(_ color: Piece.Color) -> String? {
    guard game.config.timeControl.isTimed else { return nil }
    let t = game.remaining(color)
    let total = Int(t.rounded(.up))
    if t < 20 {
      return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

private struct ToolbarButton: View {
  let title: String
  let systemImage: String
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
        Text(title)
          .font(.system(size: 11, weight: .medium, design: .rounded))
      }
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(enabled ? ChessChrome.textSecondary : ChessChrome.textSecondary.opacity(0.3))
    }
    .disabled(!enabled)
  }
}

/// Theme, piece set and coordinate toggles.
struct BoardOptionsSheet: View {
  @Binding var themeID: String
  @Binding var pieceSetRaw: String
  @Binding var showCoordinates: Bool
  @AppStorage(BoardSettings.soundKey) private var soundOn = true

  var body: some View {
    NavigationStack {
      Form {
        Section("Board") {
          Picker("Theme", selection: $themeID) {
            ForEach(BoardTheme.all) { theme in
              HStack {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: theme.light)).frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: theme.dark)).frame(width: 14, height: 14)
                Text(theme.name)
              }
              .tag(theme.id)
            }
          }
          Picker("Pieces", selection: $pieceSetRaw) {
            ForEach(PieceSetID.allCases) { set in
              HStack {
                Image(set.assetName(color: .white, kind: .knight)).resizable().frame(width: 22, height: 22)
                Text(set.displayName)
              }
              .tag(set.rawValue)
            }
          }
          Toggle("Coordinates", isOn: $showCoordinates)
        }
        Section("Sound") {
          Toggle("Move sounds", isOn: $soundOn)
        }
      }
      .navigationTitle("Options")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

/// One-line coach message above the board.
private struct CoachBanner: View {
  let text: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: Spacing.s) {
      Image(systemName: systemImage).foregroundStyle(tint)
      Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(ChessChrome.textPrimary)
      Spacer()
    }
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .background(RoundedRectangle(cornerRadius: 10).fill(ChessChrome.card))
    .padding(.horizontal, Spacing.m)
    .padding(.top, Spacing.xs)
    .accessibilityIdentifier("coach-banner")
  }
}

/// Shown when Play Coach pauses after a mistake.
private struct CoachPauseCard: View {
  let pause: CoachPause
  let onTakeBack: () -> Void
  let onShow: () -> Void
  let onContinue: () -> Void

  private var isGraded: Bool { pause.kind == .mistake || pause.kind == .blunder }
  private var tint: Color { isGraded ? pause.label.color : MoveClass.mistake.color }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      HStack(spacing: Spacing.s) {
        Group {
          if isGraded {
            Text(pause.label.glyph).font(.system(size: 12, weight: .heavy, design: .rounded))
          } else {
            Image(systemName: "hand.raised.fill").font(.system(size: 12, weight: .bold))
          }
        }
        .foregroundStyle(.white)
        .frame(width: 26, height: 26).background(Circle().fill(tint))
        Text(pause.title)
          .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(tint)
          .accessibilityIdentifier("coach-pause-title")
      }
      Text(pause.explanation)
        .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(ChessChrome.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: Spacing.s) {
        PauseButton(title: "Take back", prominent: true, action: onTakeBack).accessibilityIdentifier("coach-takeback")
        PauseButton(title: "Show me", prominent: false, action: onShow)
        PauseButton(title: "Continue", prominent: false, action: onContinue).accessibilityIdentifier("coach-continue")
      }
    }
    .padding(Spacing.l)
    .background(RoundedRectangle(cornerRadius: 16).fill(ChessChrome.bar))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.6), lineWidth: 1.5))
    .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
  }
}

private struct PauseButton: View {
  let title: String
  let prominent: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(prominent ? .white : ChessChrome.textPrimary)
        .background(RoundedRectangle(cornerRadius: 10).fill(prominent ? ChessChrome.accentGreen : ChessChrome.card))
    }
  }
}
