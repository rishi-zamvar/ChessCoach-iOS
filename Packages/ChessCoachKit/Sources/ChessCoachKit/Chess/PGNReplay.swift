import ChessKit
import Foundation

extension GameSession {
  /// Replays a PGN's main line into a session. nil if the PGN doesn't parse or a move is illegal.
  public init?(pgn: String) {
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
    let clocks = PGNClocks.parse(pgn)
    if clocks.count == history.count {
      for (i, seconds) in clocks.enumerated() { history[i].clockAfter = seconds }
    }
  }
}

/// `{[%clk h:mm:ss(.s)]}` comments, in move order.
public enum PGNClocks {
  public static func parse(_ pgn: String) -> [TimeInterval] {
    guard let regex = try? NSRegularExpression(pattern: #"\[%clk\s+(\d+):(\d{1,2}):(\d{1,2}(?:\.\d+)?)\]"#) else { return [] }
    let range = NSRange(pgn.startIndex..., in: pgn)
    return regex.matches(in: pgn, range: range).compactMap { match in
      guard let h = Range(match.range(at: 1), in: pgn), let m = Range(match.range(at: 2), in: pgn),
        let s = Range(match.range(at: 3), in: pgn),
        let hours = Double(pgn[h]), let minutes = Double(pgn[m]), let seconds = Double(pgn[s])
      else { return nil }
      return hours * 3600 + minutes * 60 + seconds
    }
  }

  /// Base seconds from a TimeControl tag like "600", "180+2" (nil for daily "1/86400" or "-").
  public static func baseSeconds(timeControl: String) -> TimeInterval? {
    guard !timeControl.contains("/"), let base = timeControl.split(separator: "+").first.flatMap({ Double($0) }), base > 0 else { return nil }
    return base
  }
}
