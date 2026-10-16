import ChessCoachKit
import ChessKit
import SwiftUI

extension GameSession {
  /// Replays a PGN's main line into a session. nil if the PGN doesn't parse or a move is illegal.
  init?(pgn: String) {
    guard let game = try? Game(pgn: pgn) else {
      // chesskit throws on movetext with no moves (a game resigned before move 1).
      let moveText = pgn.split(separator: "\n").filter { !$0.hasPrefix("[") }.joined().trimmingCharacters(in: .whitespaces)
      guard ["", "*", "1-0", "0-1", "1/2-1/2"].contains(moveText) else { return nil }
      self.init()
      return
    }
    self.init(startFEN: game.startingPosition?.fen ?? GameSession.standardFEN)
    let tree = game.moves
    var index = game.startingIndex
    while tree.hasIndex(after: index) {
      index = tree.index(after: index)
      guard let move = tree[index], case .applied = apply(uci: move.lan) else { return nil }
    }
  }
}

/// Win / loss / draw from the user's side of a saved game.
enum GameOutcome: String {
  case win = "W", loss = "L", draw = "D"

  init(userColor: String, result: String) {
    switch result {
    case "1-0": self = userColor == "white" ? .win : .loss
    case "0-1": self = userColor == "black" ? .win : .loss
    default: self = .draw
    }
  }

  var color: Color {
    switch self {
    case .win: Palette.success
    case .loss: Palette.danger
    case .draw: Palette.textMuted
    }
  }
}

extension GameRecord {
  var outcome: GameOutcome { GameOutcome(userColor: userColor, result: result) }
  var opponentName: String { userColor == "white" ? black : white }
  var terminationText: String { Termination(rawValue: termination)?.displayName ?? termination.capitalized }

  /// "300+2" → "5 | 2", "600+0" → "10 min", "-" → "No clock" (mirrors `TimeControl.label`).
  var timeControlText: String {
    let parts = timeControl.split(separator: "+").compactMap { Int($0) }
    guard parts.count == 2 else { return "No clock" }
    return parts[1] > 0 ? "\(parts[0] / 60) | \(parts[1])" : "\(parts[0] / 60) min"
  }
}

/// Small rounded-square W/L/D badge.
struct OutcomeBadge: View {
  let outcome: GameOutcome

  var body: some View {
    Text(outcome.rawValue)
      .font(.system(size: 15, weight: .bold, design: .rounded))
      .foregroundStyle(Palette.textOnDark)
      .frame(width: 32, height: 32)
      .background(outcome.color, in: RoundedRectangle(cornerRadius: Spacing.cornerSmall, style: .continuous))
      .accessibilityLabel(outcome == .win ? "Win" : outcome == .loss ? "Loss" : "Draw")
  }
}
