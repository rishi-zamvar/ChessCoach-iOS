import ChessKit
import Foundation

/// What a coach game trains. Picked from how your recent games went (or your puzzle skills).
public enum CoachFocus: String, Codable, CaseIterable, Sendable {
  case hangingOwn, freePieces, mates, tactics

  public var title: String {
    switch self {
    case .hangingOwn: "Keeping your pieces safe"
    case .freePieces: "Spotting free pieces"
    case .mates: "Finding checkmates"
    case .tactics: "Forks and pins"
    }
  }

  /// Said at the start of the game.
  public var intro: String {
    switch self {
    case .hangingOwn: "Today we keep every piece safe. Before each move, check what can be taken."
    case .freePieces: "Today we hunt for free pieces. Before each move, check what you can take."
    case .mates: "Today we look for checkmates. Before each move, look at every check."
    case .tactics: "Today we look for forks and pins. Look for pieces that line up."
    }
  }

  /// Puzzle skills that measure this focus (SkillCatalog ids).
  static let skills: [CoachFocus: [String]] = [
    .freePieces: ["C1"], .mates: ["B1", "B3", "B4", "B5"], .tactics: ["C2", "C3", "C4"],
  ]

  /// Bot moves between deliberate set-ups for this focus.
  var giftEvery: Int { self == .mates ? 6 : 3 }
}

/// How often each kind of slip happened, decayed across games.
public struct WeaknessTally: Codable, Equatable, Sendable {
  public var hung = 0.0
  public var missedFree = 0.0
  public var missedMate = 0.0
  public var missedTactic = 0.0

  public init(hung: Double = 0, missedFree: Double = 0, missedMate: Double = 0, missedTactic: Double = 0) {
    self.hung = hung
    self.missedFree = missedFree
    self.missedMate = missedMate
    self.missedTactic = missedTactic
  }

  public var isEmpty: Bool { hung + missedFree + missedMate + missedTactic == 0 }

  /// Fold one game's counts in; older games fade.
  public func adding(_ game: WeaknessTally) -> WeaknessTally {
    WeaknessTally(
      hung: hung * 0.7 + game.hung, missedFree: missedFree * 0.7 + game.missedFree,
      missedMate: missedMate * 0.7 + game.missedMate, missedTactic: missedTactic * 0.7 + game.missedTactic)
  }

  mutating func record(_ kind: HoldUpKind) {
    switch kind {
    case .hungPiece: hung += 1
    case .missedFree: missedFree += 1
    case .missedMate: missedMate += 1
    case .missedTactic, .allowsTactic: missedTactic += 1
    case .mistake, .blunder: break
    }
  }

  /// The biggest weakness; with no game data, the weakest puzzle skill; else free pieces.
  public func focus(puzzleRatings: [String: Double] = [:]) -> CoachFocus {
    if !isEmpty {
      let scores: [(CoachFocus, Double)] = [(.hangingOwn, hung), (.freePieces, missedFree), (.mates, missedMate), (.tactics, missedTactic)]
      return scores.max { $0.1 < $1.1 }!.0
    }
    let averages = CoachFocus.skills.compactMap { focus, ids -> (CoachFocus, Double)? in
      let rated = ids.compactMap { puzzleRatings[$0] }
      return rated.isEmpty ? nil : (focus, rated.reduce(0, +) / Double(rated.count))
    }
    return averages.min { $0.1 < $1.1 }?.0 ?? .freePieces
  }
}

/// Engine-free board scans: fast enough to run on every move.
public enum BoardScan {
  public static func legalUCIs(fen: String) -> [String] {
    let session = GameSession(startFEN: fen)
    let side = session.sideToMove
    return session.position.pieces.filter { $0.color == side }.flatMap { piece in
      session.legalTargets(from: piece.square).map { to in
        let promotes = piece.kind == .pawn && (to.rank.value == 8 || to.rank.value == 1)
        return piece.square.notation + to.notation + (promotes ? "q" : "")
      }
    }
  }

  /// A move that mates right away for the side to move.
  public static func mateInOne(fen: String) -> String? {
    legalUCIs(fen: fen).first { uci in
      var s = GameSession(startFEN: fen)
      guard case .applied(let played) = s.apply(uci: uci) else { return false }
      return played.move.checkState == .checkmate
    }
  }

  /// A capture that wins a loose enemy piece (by exchange), biggest first.
  public static func freeCapture(fen: String) -> (uci: String, piece: Piece)? {
    guard let side = Position(fen: fen)?.sideToMove else { return nil }
    let loose = FactExtractor.hangingPieces(fen: fen, of: side.opposite)
    let moves = legalUCIs(fen: fen)
    for target in loose {
      if let uci = moves.first(where: { String($0.dropFirst(2).prefix(2)) == target.square.notation }) {
        return (uci, target)
      }
    }
    return nil
  }

  /// A fork, pin or skewer whose moving piece isn't simply lost.
  public static func tactic(fen: String) -> (uci: String, motif: Motif)? {
    guard let side = Position(fen: fen)?.sideToMove else { return nil }
    for uci in legalUCIs(fen: fen) {
      guard let facts = FactExtractor.moveFacts(fen: fen, uci: uci),
        let motif = [Motif.fork, .pin, .skewer].first(where: facts.motifs.contains)
      else { continue }
      var s = GameSession(startFEN: fen)
      s.apply(uci: uci)
      let to = String(uci.dropFirst(2).prefix(2))
      if !FactExtractor.hangingPieces(fen: s.position.fen, of: side).contains(where: { $0.square.notation == to }) {
        return (uci, motif)
      }
    }
    return nil
  }

  /// Bot moves that set up the focus for the learner: a loose piece, a mate in one, a tactic.
  public static func gifts(fen: String, focus: CoachFocus, limit: Int = 3) -> [String] {
    guard focus != .hangingOwn, let bot = Position(fen: fen)?.sideToMove else { return [] }
    let looseBefore = Set(FactExtractor.hangingPieces(fen: fen, of: bot).map(\.square))
    var found: [String] = []
    for uci in legalUCIs(fen: fen) where found.count < limit {
      var s = GameSession(startFEN: fen)
      guard case .applied(let played) = s.apply(uci: uci), played.move.checkState != .checkmate else { continue }
      let after = s.position.fen
      let hit: Bool
      switch focus {
      case .freePieces:
        hit = FactExtractor.hangingPieces(fen: after, of: bot).contains { $0.kind != .pawn && !looseBefore.contains($0.square) }
      case .mates: hit = mateInOne(fen: after) != nil
      case .tactics: hit = tactic(fen: after) != nil
      case .hangingOwn: hit = false
      }
      if hit { found.append(uci) }
    }
    return found
  }
}

public enum HoldUpKind: String, Codable, Sendable {
  case hungPiece, missedMate, missedFree, missedTactic, allowsTactic, mistake, blunder
}

/// Why the coach stopped you, in fixed words, with squares to mark.
public struct HoldUp: Equatable, Sendable {
  public var kind: HoldUpKind
  public var line: String
  public var marks: [Square: AnnotationColor]

  /// Rules, in order. `label` is the engine's verdict on the move; `focus` widens what counts.
  public static func check(fenBefore: String, played uci: String, label: MoveClass, focus: CoachFocus?) -> HoldUp? {
    guard let mover = Position(fen: fenBefore)?.sideToMove else { return nil }
    var s = GameSession(startFEN: fenBefore)
    guard case .applied(let played) = s.apply(uci: uci), played.move.checkState != .checkmate else { return nil }
    let after = s.position.fen
    let slipped = [MoveClass.inaccuracy, .mistake, .blunder, .miss].contains(label)

    let looseBefore = Set(FactExtractor.hangingPieces(fen: fenBefore, of: mover).map(\.square))
    if slipped, let loose = FactExtractor.hangingPieces(fen: after, of: mover).first(where: {
      !looseBefore.contains($0.square) && ($0.kind != .pawn || focus == .hangingOwn)
    }) {
      return HoldUp(
        kind: .hungPiece, line: "Hold up. Your \(FactExtractor.name(of: loose.kind)) on \(loose.square.notation) has no defender.",
        marks: [loose.square: .red])
    }
    if let mate = BoardScan.mateInOne(fen: fenBefore), mate != uci {
      return HoldUp(kind: .missedMate, line: "Hold up. You had checkmate in one. Can you find it?", marks: [:])
    }
    if slipped, let free = BoardScan.freeCapture(fen: fenBefore), free.uci.dropFirst(2).prefix(2) != uci.dropFirst(2).prefix(2),
      free.piece.kind != .pawn || focus == .freePieces
    {
      return HoldUp(
        kind: .missedFree, line: "Hold up. Their \(FactExtractor.name(of: free.piece.kind)) on \(free.piece.square.notation) was free.",
        marks: [free.piece.square: .green])
    }
    if label == .blunder || label == .mistake {
      return HoldUp(kind: label == .blunder ? .blunder : .mistake, line: "Hold up. That move is a \(label == .blunder ? "blunder" : "mistake").", marks: [:])
    }
    return nil
  }

  /// Fixed lines for the kinds the AI reviewer may ask for.
  public static func reviewed(_ kind: HoldUpKind) -> HoldUp? {
    switch kind {
    case .missedTactic: HoldUp(kind: kind, line: "Hold up. There was a stronger idea here. Take another look.", marks: [:])
    case .allowsTactic: HoldUp(kind: kind, line: "Hold up. Check what their pieces can do after this move.", marks: [:])
    default: nil
    }
  }
}
