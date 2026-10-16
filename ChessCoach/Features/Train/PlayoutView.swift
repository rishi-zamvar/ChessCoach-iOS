import ChessCoachKit
import ChessKit
import SwiftUI

/// Play-it-out practice (basic mates, king-and-pawn): you play the winning side from
/// the lesson position; Stockfish defends as well as it can.
struct PlayoutView: View {
  let practice: Practice
  let onFinished: (_ wins: Int, _ total: Int) -> Void

  @Environment(AppEnvironment.self) private var env
  @Environment(AnalysisService.self) private var analysis
  @AppStorage(BoardSettings.themeKey) private var themeID = BoardTheme.default.id
  @AppStorage(BoardSettings.piecesKey) private var pieceSetRaw = PieceSetID.default.rawValue

  @State private var round = 0
  @State private var wins = 0
  @State private var game = GameSession()
  @State private var interaction = BoardInteraction()
  @State private var outcome: Bool?  // nil = playing
  @State private var message = ""
  @State private var thinking = false

  private var total: Int { max(1, practice.count) }
  private var startFEN: String { practice.fen ?? GameSession.standardFEN }
  private var userColor: Piece.Color { Position(fen: startFEN)?.sideToMove ?? .white }
  private var plyLimit: Int { practice.goal == .promote ? 40 : 70 }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 4) {
        Text("Play it out · \(round + 1) of \(total)")
          .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(ChessChrome.textSecondary)
        Text(message).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(ChessChrome.textPrimary)
          .multilineTextAlignment(.center).padding(.horizontal)
          .accessibilityIdentifier("playout-message")
      }
      .padding(.vertical, Spacing.s)
      BoardView(
        position: game.position,
        highlights: BoardHighlights.make(session: game, ply: game.history.count, interaction: interaction),
        theme: BoardTheme.named(themeID), pieceSet: PieceSetID(rawValue: pieceSetRaw) ?? .default,
        flipped: userColor == .black,
        interactive: outcome == nil && !thinking,
        onTap: { square in
          if case .move(let from, let to) = interaction.tap(square, session: game, userColor: userColor) { play(from, to) }
        },
        onDragBegan: { interaction.dragBegan(at: $0, session: game, userColor: userColor) },
        onDragEnded: { square in
          if case .move(let from, let to) = interaction.dragEnded(at: square, session: game, userColor: userColor) { play(from, to) }
        },
        onDragCancelled: { interaction.dragCancelled() })
      if let last = game.lastMove {
        MoveNote(
          who: last.color == userColor ? "You" : "Stockfish", isYou: last.color == userColor, san: last.san,
          text: Explainer.reason(fen: game.fen(atPly: game.history.count - 1), uci: last.uci) ?? last.san, compact: true)
          .padding(.horizontal, Spacing.m).padding(.top, Spacing.s)
          .accessibilityIdentifier("playout-caption")
      }
      Spacer(minLength: 0)
      HStack(spacing: Spacing.s) {
        if outcome == false {
          PuzzleButton(title: "Try again", systemImage: "arrow.counterclockwise", prominent: true) { reset() }
            .accessibilityIdentifier("playout-retry")
          PuzzleButton(title: round + 1 < total ? "Skip" : "Finish", systemImage: "arrow.right") { next() }
        } else if outcome == true {
          PuzzleButton(title: "Replay", systemImage: "arrow.counterclockwise") { reset() }
          PuzzleButton(title: round + 1 < total ? "Next" : "Finish", systemImage: "arrow.right", prominent: true) { next() }
        } else {
          PuzzleButton(title: "Take back", systemImage: "arrow.uturn.backward") { takeBack() }
            .disabled(thinking || game.history.isEmpty)
            .accessibilityIdentifier("playout-takeback")
          PuzzleButton(title: "Restart", systemImage: "arrow.counterclockwise") { reset() }
            .disabled(thinking)
        }
      }
      .padding(Spacing.m)
    }
    .onAppear {
      analysis.beginForegroundEngineUse()
      reset()
    }
    .onDisappear { analysis.endForegroundEngineUse() }
  }

  private var goalText: String {
    switch practice.goal {
    case .mate: "Checkmate the lone king."
    case .promote: "Promote your pawn."
    case .draw: "Hold the draw."
    case nil: "Win the position."
    }
  }

  /// Undoes your last move (and Stockfish's reply to it).
  private func takeBack() {
    guard !thinking, let last = game.lastMove else { return }
    game.undo(last.color == userColor ? 1 : min(2, game.history.count))
    interaction.reset()
    message = goalText
  }

  private func reset() {
    if outcome == true { wins -= 1 }  // replaying a won round doesn't count twice
    game = GameSession(startFEN: startFEN)
    interaction.reset()
    outcome = nil
    message = goalText
  }

  private func play(_ from: Square, _ to: Square) {
    let promo: Piece.Kind? = game.isPromotion(from: from, to: to) ? .queen : nil
    guard case .applied(let played) = game.apply(from: from, to: to, promotion: promo) else { return }
    env.sounds.play(SoundEvent.forMove(played, gameOver: game.isOver))
    if judge(after: played) { return }
    defend()
  }

  /// Returns true if the round ended.
  private func judge(after played: PlayedMove) -> Bool {
    if practice.goal == .promote, played.move.promotedPiece != nil, played.color == userColor {
      return end(true, "Promoted! That's the technique.")
    }
    if let result = game.result {
      if result.termination == .checkmate, result.winner == userColor { return end(true, "Checkmate! Nicely done.") }
      if result.termination == .stalemate { return end(false, "Stalemate — the king had no moves but wasn't in check. Leave it a square.") }
      return end(practice.goal == .draw, result.termination == .checkmate ? "That's mate against you." : "It's a draw (\(result.termination.displayName.lowercased())).")
    }
    let myMaterial = game.position.pieces.filter { $0.color == userColor && $0.kind != .king }.count
    let startMaterial = (Position(fen: startFEN)?.pieces ?? []).filter { $0.color == userColor && $0.kind != .king }.count
    if myMaterial < startMaterial, practice.goal != .promote || played.move.promotedPiece == nil {
      return end(false, "Your piece was taken. Keep it protected — or away from the king.")
    }
    if game.history.count >= plyLimit { return end(false, "Out of moves. Push the king to the edge step by step.") }
    return false
  }

  private func defend() {
    guard let host = env.engineHost else { return }
    thinking = true
    let fen = game.position.fen
    Task {
      defer { thinking = false }
      guard let reply = try? await host.search(.stockfish, fen: fen, limit: .depth(12)), game.position.fen == fen,
        case .applied(let played) = game.apply(uci: reply.bestMove)
      else { return }
      env.sounds.play(SoundEvent.forMove(played, gameOver: game.isOver))
      _ = judge(after: played)
    }
  }

  @discardableResult
  private func end(_ success: Bool, _ text: String) -> Bool {
    outcome = success
    message = text
    if success { wins += 1 }
    return true
  }

  private func next() {
    if round + 1 >= total {
      onFinished(wins, total)
    } else {
      round += 1
      reset()
    }
  }
}
