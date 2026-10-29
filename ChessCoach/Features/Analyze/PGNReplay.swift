import ChessCoachKit
import ChessKit
import SwiftUI

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
    var parts = timeControl.split(separator: "+").compactMap { Int($0) }
    if parts.count == 1 { parts.append(0) }  // chess.com sends "600" for 10|0
    guard parts.count == 2, parts[0] > 0 else { return timeControl.contains("/") ? "Daily" : "No clock" }
    return parts[1] > 0 ? "\(parts[0] / 60) | \(parts[1])" : "\(parts[0] / 60) min"
  }
}

/// Small rounded-square W/L/D badge.
struct OutcomeBadge: View {
  let outcome: GameOutcome

  var body: some View {
    Text(outcome.rawValue)
      .font(.system(.subheadline).weight(.bold))
      .foregroundStyle(Palette.textOnDark)
      .frame(width: 32, height: 32)
      .background(outcome.color, in: RoundedRectangle(cornerRadius: Spacing.cornerSmall, style: .continuous))
      .accessibilityLabel(outcome == .win ? "Win" : outcome == .loss ? "Loss" : "Draw")
  }
}
