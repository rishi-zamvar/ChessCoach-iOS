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

  private var theme: BoardTheme { BoardTheme.named(themeID) }
  private var pieceSet: PieceSetID { PieceSetID(rawValue: pieceSetRaw) ?? .default }
  private var topColor: Piece.Color { game.flipped ? .white : .black }
  private var bottomColor: Piece.Color { topColor.opposite }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { context in
      VStack(spacing: 0) {
        header
        MoveStrip(history: game.session.history, currentPly: game.viewPly) { game.jump(toPly: $0) }
        Spacer(minLength: Spacing.s)
        PlayerBar(
          name: name(for: topColor), rating: rating(for: topColor), color: topColor,
          captured: game.session.captured(by: topColor), advantage: advantage(for: topColor),
          clock: clockText(topColor), clockActive: clockActive(topColor), lowTime: game.isLowTime(topColor),
          thinking: game.phase == .botThinking && topColor != game.userColor, pieceSet: pieceSet)
        board
        PlayerBar(
          name: name(for: bottomColor), rating: rating(for: bottomColor), color: bottomColor,
          captured: game.session.captured(by: bottomColor), advantage: advantage(for: bottomColor),
          clock: clockText(bottomColor), clockActive: clockActive(bottomColor), lowTime: game.isLowTime(bottomColor),
          thinking: game.phase == .botThinking && bottomColor != game.userColor, pieceSet: pieceSet)
        Spacer(minLength: Spacing.s)
        toolbar
      }
      .onChange(of: context.date) { _, _ in game.tick() }
    }
    .background(ChessChrome.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
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
    .onAppear { game.start() }
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

  private var header: some View {
    HStack {
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .accessibilityIdentifier("game-close")
      Spacer()
      Text(game.config.timeControl.isTimed ? game.config.timeControl.label : "Casual")
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
      if game.isOver {
        ToolbarButton(title: "New", systemImage: "plus") { onClose() }
      } else {
        ToolbarButton(title: "Draw", systemImage: "equal.circle") {
          if !game.offerDraw() { drawDeclined = true }
        }
        ToolbarButton(title: "Resign", systemImage: "flag") { confirmResign = true }
          .accessibilityIdentifier("toolbar-resign")
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
