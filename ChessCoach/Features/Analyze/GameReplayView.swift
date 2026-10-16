import ChessCoachKit
import ChessKit
import SwiftUI

/// Read-only step-through of a saved game on the dark board chrome.
struct GameReplayView: View {
  let game: GameRecord
  private let session: GameSession?
  @State private var ply: Int

  @Environment(\.dismiss) private var dismiss
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue
  @AppStorage(BoardSettings.coordinatesKey) private var showCoordinates = true

  init(game: GameRecord) {
    self.game = game
    let session = GameSession(pgn: game.pgn)
    self.session = session
    _ply = State(initialValue: session?.history.count ?? 0)
  }

  private var lastPly: Int { session?.history.count ?? 0 }

  var body: some View {
    VStack(spacing: 0) {
      header
      if let session {
        MoveStrip(history: session.history, currentPly: ply) { ply = $0 }
        Spacer(minLength: Spacing.s)
        BoardView(
          position: Position(fen: session.fen(atPly: ply)) ?? .standard,
          highlights: BoardHighlights.make(session: session, ply: ply, interaction: BoardInteraction()),
          theme: BoardTheme.named(themeID),
          pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
          flipped: game.userColor == "black",
          showCoordinates: showCoordinates,
          interactive: false)
        Text("Game Review arrives in M2")
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(ChessChrome.textSecondary)
          .padding(.top, Spacing.m)
        Spacer(minLength: Spacing.s)
        controls
      } else {
        Spacer()
        Text("This game's moves couldn't be read.")
          .font(.system(size: 15, weight: .medium, design: .rounded))
          .foregroundStyle(ChessChrome.textSecondary)
        Spacer()
      }
    }
    .background(ChessChrome.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
    .toolbar(.hidden, for: .navigationBar)
  }

  private var header: some View {
    HStack {
      Button { dismiss() } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Back")
      Spacer()
      VStack(spacing: 2) {
        Text("\(game.white) vs \(game.black)")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundStyle(ChessChrome.textPrimary)
        Text("\(game.result) · \(game.terminationText)")
          .font(.system(size: 13, weight: .medium, design: .rounded))
      }
      .lineLimit(1)
      Spacer()
      OutcomeBadge(outcome: game.outcome)
        .padding(.trailing, Spacing.s)
    }
    .foregroundStyle(ChessChrome.textSecondary)
    .padding(.horizontal, Spacing.s)
    .background(ChessChrome.bar)
  }

  private var controls: some View {
    HStack(spacing: 0) {
      step("backward.end.fill", "First move", enabled: ply > 0) { ply = 0 }
      step("chevron.left", "Previous move", enabled: ply > 0) { ply -= 1 }
      step("chevron.right", "Next move", enabled: ply < lastPly) { ply += 1 }
      step("forward.end.fill", "Last move", enabled: ply < lastPly) { ply = lastPly }
    }
    .padding(.vertical, Spacing.xs)
    .background(ChessChrome.bar)
  }

  private func step(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
    .foregroundStyle(enabled ? ChessChrome.textPrimary : ChessChrome.textSecondary.opacity(0.35))
    .disabled(!enabled)
    .accessibilityLabel(label)
  }
}
