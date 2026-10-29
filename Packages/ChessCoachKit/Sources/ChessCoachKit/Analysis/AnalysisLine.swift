import ChessKit
import Foundation

/// The analysis board's line (spec W4): any legal move for either side from a start position,
/// with undo/redo (playing a new move from earlier replaces what came after) and PGN export.
public struct AnalysisLine: Sendable, Equatable {
  public let startFEN: String
  public private(set) var moves: [String]
  /// How many of `moves` are on the board.
  public private(set) var cursor: Int

  public init(startFEN: String, moves: [String] = [], cursor: Int? = nil) {
    self.startFEN = startFEN
    var session = GameSession(startFEN: startFEN)
    self.moves = moves.prefix { if case .applied = session.apply(uci: $0) { true } else { false } }.map { $0 }
    self.cursor = min(cursor ?? self.moves.count, self.moves.count)
  }

  /// The game at the cursor.
  public var session: GameSession {
    var s = GameSession(startFEN: startFEN)
    for uci in moves.prefix(cursor) { s.apply(uci: uci) }
    return s
  }

  public var fen: String { session.position.fen }
  public var san: [String] { session.history.map(\.san) }
  public var lastMove: String? { cursor > 0 ? moves[cursor - 1] : nil }
  public var canUndo: Bool { cursor > 0 }
  public var canRedo: Bool { cursor < moves.count }

  @discardableResult
  public mutating func play(uci: String) -> Bool {
    var s = session
    guard case .applied(let played) = s.apply(uci: uci) else { return false }
    moves = Array(moves.prefix(cursor)) + [played.uci]
    cursor += 1
    return true
  }

  @discardableResult
  public mutating func undo() -> Bool {
    guard canUndo else { return false }
    cursor -= 1
    return true
  }

  @discardableResult
  public mutating func redo() -> Bool {
    guard canRedo else { return false }
    cursor += 1
    return true
  }

  public mutating func reset() { cursor = 0 }

  public mutating func go(to ply: Int) { cursor = max(0, min(ply, moves.count)) }

  /// The whole line (not just to the cursor) as PGN, with the start position.
  public var pgn: String {
    var s = GameSession(startFEN: startFEN)
    for uci in moves { s.apply(uci: uci) }
    let whiteFirst = (Position(fen: startFEN)?.sideToMove ?? .white) == .white
    let fullmove = Int(startFEN.split(separator: " ").last.map(String.init) ?? "1") ?? 1
    var parts: [String] = []
    for (i, move) in s.history.enumerated() {
      let plyFromWhite = i + (whiteFirst ? 0 : 1)
      let number = fullmove + plyFromWhite / 2
      if plyFromWhite % 2 == 0 { parts.append("\(number).") } else if i == 0 { parts.append("\(number)...") }
      parts.append(move.san)
    }
    let header = startFEN == GameSession.standardFEN ? "" : "[SetUp \"1\"]\n[FEN \"\(startFEN)\"]\n\n"
    return header + parts.joined(separator: " ")
  }
}
