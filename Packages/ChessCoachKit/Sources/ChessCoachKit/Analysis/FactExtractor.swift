import ChessKit
import Foundation

/// Tactical themes we can detect deterministically.
public enum Motif: String, Codable, CaseIterable, Sendable {
  case mate, check, fork, pin, skewer, discoveredAttack, backRankMate, mateThreat
  case winsMaterial, hangingPiece, promotion

  public var displayName: String {
    switch self {
    case .mate: "Checkmate"
    case .check: "Check"
    case .fork: "Fork"
    case .pin: "Pin"
    case .skewer: "Skewer"
    case .discoveredAttack: "Discovered attack"
    case .backRankMate: "Back-rank mate"
    case .mateThreat: "Mate threat"
    case .winsMaterial: "Wins material"
    case .hangingPiece: "Hanging piece"
    case .promotion: "Promotion"
    }
  }
}

public enum GamePhaseKind: String, Codable, Sendable {
  case opening, middlegame, endgame
}

public struct PieceFact: Codable, Equatable, Sendable {
  public var kind: String
  public var square: String

  init(_ piece: Piece) {
    kind = FactExtractor.name(of: piece.kind)
    square = piece.square.notation
  }
}

/// What a single move did, in checkable facts.
public struct MoveFacts: Codable, Equatable, Sendable {
  public var san: String
  public var uci: String
  public var motifs: [Motif]
  /// Enemy pieces the moved piece attacks after the move (fork targets etc.).
  public var targets: [PieceFact]
  /// Material the mover can win on the move's square/targets by exchange (≥ 0).
  public var materialWon: Int
}

/// Facts about one played move, its engine alternative and the punishment.
public struct FactSheet: Codable, Equatable, Sendable {
  public var mover: String
  public var played: MoveFacts
  /// The mover's pieces left en prise after the played move.
  public var hangingAfter: [PieceFact]
  public var best: MoveFacts?
  public var bestLineSAN: [String]
  /// Opponent's best reply to the played move.
  public var punish: MoveFacts?
  public var punishLineSAN: [String]
  public var phase: GamePhaseKind

  /// Every SAN and square mentioned, used to validate generated text.
  public var vocabulary: Set<String> {
    var words = Set(bestLineSAN + punishLineSAN + [played.san])
    for facts in [played, best, punish].compactMap({ $0 }) {
      words.insert(facts.san)
      for t in facts.targets { words.insert(t.square) }
      words.insert(String(facts.uci.prefix(2)))
      words.insert(String(facts.uci.dropFirst(2).prefix(2)))
    }
    for h in hangingAfter { words.insert(h.square) }
    return words
  }
}

/// FEN string helpers.
public enum FENTools {
  /// The same position with the other side to move (en passant cleared) — a "null move".
  /// (chesskit's `toggleSideToMove` does not update the side-to-move field.)
  public static func passTurn(_ fen: String) -> String {
    var fields = fen.split(separator: " ").map(String.init)
    guard fields.count >= 4 else { return fen }
    fields[1] = fields[1] == "w" ? "b" : "w"
    fields[3] = "-"
    return fields.joined(separator: " ")
  }

  /// FEN without the halfmove/fullmove counters, used as a cache key.
  public static func key(_ fen: String) -> String {
    fen.split(separator: " ").prefix(4).joined(separator: " ")
  }
}

/// Deterministic tactic and safety facts for positions and moves.
public enum FactExtractor {
  /// Facts about one move `uci` played in `fen`.
  public static func moveFacts(fen: String, uci: String) -> MoveFacts? {
    var session = GameSession(startFEN: fen)
    let before = session.position
    guard case .applied(let played) = session.apply(uci: uci) else { return nil }
    let after = session.position
    let mover = played.color
    let mapBefore = BoardMap(before)
    let mapAfter = BoardMap(after)
    var motifs: [Motif] = []

    if played.move.checkState == .checkmate {
      motifs.append(.mate)
      if isBackRankMate(map: mapAfter, matedColor: mover.opposite, mover: played.move.piece) { motifs.append(.backRankMate) }
    } else if played.move.checkState == .check {
      motifs.append(.check)
    }
    if played.move.promotedPiece != nil { motifs.append(.promotion) }

    // Material won by the capture itself (captured value minus what the exchange gives back).
    var materialWon = 0
    if case .capture(let captured) = played.move.result {
      let recapture = StaticExchange.evaluate(mapAfter, square: played.move.end, by: mover.opposite)
      materialWon = max(0, PieceValue.of(captured.kind) - recapture)
      if materialWon >= 2 { motifs.append(.winsMaterial) }
      if mapBefore.attackers(of: played.move.end, by: mover.opposite).isEmpty, captured.kind != .pawn {
        motifs.append(.hangingPiece)
      }
    }

    guard let movedPiece = mapAfter[played.move.end] else {
      return MoveFacts(san: played.san, uci: uci, motifs: motifs, targets: [], materialWon: materialWon)
    }
    let targets = forkTargets(map: mapAfter, piece: movedPiece)
    if targets.count >= 2 { motifs.append(.fork) }
    if let lineMotif = lineTactic(map: mapAfter, piece: movedPiece) { motifs.append(lineMotif) }
    if discoveredAttack(before: mapBefore, after: mapAfter, mover: mover, moved: played.move.end) { motifs.append(.discoveredAttack) }
    if !motifs.contains(.mate), threatensMate(afterFEN: after.fen) { motifs.append(.mateThreat) }

    return MoveFacts(
      san: played.san, uci: uci, motifs: Array(NSOrderedSet(array: motifs)) as? [Motif] ?? motifs,
      targets: targets.map(PieceFact.init), materialWon: materialWon)
  }

  /// Full fact sheet for a played move with optional engine lines (UCI).
  public static func sheet(fen: String, played uci: String, bestLine: [String], punishLine: [String], ply: Int) -> FactSheet? {
    guard let playedFacts = moveFacts(fen: fen, uci: uci) else { return nil }
    var session = GameSession(startFEN: fen)
    let mover = session.sideToMove
    session.apply(uci: uci)
    let afterFEN = session.position.fen
    let best = bestLine.first.flatMap { $0 == uci ? nil : moveFacts(fen: fen, uci: $0) }
    let punish = punishLine.first.flatMap { moveFacts(fen: afterFEN, uci: $0) }
    return FactSheet(
      mover: mover == .white ? "white" : "black",
      played: playedFacts,
      hangingAfter: hangingPieces(fen: afterFEN, of: mover).map(PieceFact.init),
      best: best,
      bestLineSAN: sanLine(fen: fen, ucis: Array(bestLine.prefix(6))),
      punish: punish,
      punishLineSAN: sanLine(fen: afterFEN, ucis: Array(punishLine.prefix(6))),
      phase: phase(fen: fen, ply: ply))
  }

  /// Pieces of `color` that the opponent can win by exchange (SEE > 0).
  public static func hangingPieces(fen: String, of color: Piece.Color) -> [Piece] {
    guard let position = Position(fen: fen) else { return [] }
    let map = BoardMap(position)
    return map.pieces(of: color)
      .filter { $0.kind != .king && StaticExchange.evaluate(map, square: $0.square, by: color.opposite) > 0 }
      .sorted { PieceValue.of($0.kind) > PieceValue.of($1.kind) }
  }

  /// Converts a UCI line to SAN, stopping at the first illegal move.
  public static func sanLine(fen: String, ucis: [String]) -> [String] {
    var session = GameSession(startFEN: fen)
    var result: [String] = []
    for uci in ucis {
      guard case .applied(let played) = session.apply(uci: uci) else { break }
      result.append(played.san)
    }
    return result
  }

  public static func phase(fen: String, ply: Int) -> GamePhaseKind {
    guard let position = Position(fen: fen) else { return .middlegame }
    let nonPawn = position.pieces.filter { $0.kind != .pawn && $0.kind != .king }
    let material = nonPawn.reduce(0) { $0 + PieceValue.of($1.kind) }
    let queens = nonPawn.filter { $0.kind == .queen }.count
    if material <= 26 || (queens == 0 && material <= 32) { return .endgame }
    return ply < 20 ? .opening : .middlegame
  }

  public static func name(of kind: Piece.Kind) -> String {
    switch kind {
    case .pawn: "pawn"
    case .knight: "knight"
    case .bishop: "bishop"
    case .rook: "rook"
    case .queen: "queen"
    case .king: "king"
    }
  }

  // MARK: - Detectors

  /// Enemy pieces attacked by `piece` that are worth attacking: the king, anything
  /// more valuable than the attacker, or anything undefended.
  static func forkTargets(map: BoardMap, piece: Piece) -> [Piece] {
    let attacked = map.attacks(of: piece).compactMap { map[$0] }.filter { $0.color != piece.color }
    let attackerSafe = StaticExchange.evaluate(map, square: piece.square, by: piece.color.opposite) == 0
      || map[piece.square].map { _ in true } == true && attacked.contains { $0.kind == .king }
    guard attackerSafe else { return [] }
    return attacked.filter { target in
      target.kind == .king
        || PieceValue.of(target.kind) > PieceValue.of(piece.kind)
        || map.attackers(of: target.square, by: target.color).isEmpty
    }
  }

  /// Pin (front piece shields a more valuable piece / king) or skewer (front piece
  /// is the more valuable one) along one of `piece`'s lines.
  static func lineTactic(map: BoardMap, piece: Piece) -> Motif? {
    for direction in BoardMap.directions(for: piece.kind) {
      let ray = map.ray(from: piece.square, direction: direction)
      guard let frontSquare = ray.last, let front = map[frontSquare], front.color != piece.color else { continue }
      var behindMap = map
      behindMap.remove(frontSquare)
      let behindRay = behindMap.ray(from: piece.square, direction: direction)
      guard let backSquare = behindRay.last, backSquare != frontSquare, let back = map[backSquare], back.color == front.color else { continue }
      let frontValue = PieceValue.of(front.kind)
      let backValue = PieceValue.of(back.kind)
      if backValue > frontValue, front.kind != .pawn { return .pin }
      if frontValue > backValue, back.kind != .pawn, frontValue > PieceValue.of(piece.kind) || front.kind == .king { return .skewer }
    }
    return nil
  }

  /// Another of the mover's sliders gained an attack on a valuable enemy piece.
  static func discoveredAttack(before: BoardMap, after: BoardMap, mover: Piece.Color, moved: Square) -> Bool {
    for slider in after.pieces(of: mover) where slider.square != moved && [.bishop, .rook, .queen].contains(slider.kind) {
      guard let old = before[slider.square], old == slider else { continue }
      let newTargets = Set(after.attacks(of: slider)).subtracting(before.attacks(of: old))
      for square in newTargets {
        if let target = after[square], target.color != mover,
          target.kind == .king || PieceValue.of(target.kind) > PieceValue.of(slider.kind)
            || after.attackers(of: square, by: target.color).isEmpty && target.kind != .pawn
        {
          return true
        }
      }
    }
    return false
  }

  /// If the opponent passed, could the mover mate in one?
  static func threatensMate(afterFEN: String) -> Bool {
    guard let position = Position(fen: FENTools.passTurn(afterFEN)) else { return false }
    let board = Board(position: position)
    if case .check = board.state { return false }  // passing while giving check is not a real line
    let attacker = position.sideToMove
    for piece in position.pieces where piece.color == attacker {
      for target in board.legalMoves(forPieceAt: piece.square) {
        var copy = board
        guard var move = copy.move(pieceAt: piece.square, to: target) else { continue }
        if case .promotion = copy.state { move = copy.completePromotion(of: move, to: .queen) }
        if move.checkState == .checkmate { return true }
      }
    }
    return false
  }

  static func isBackRankMate(map: BoardMap, matedColor: Piece.Color, mover: Piece) -> Bool {
    guard let king = map.king(of: matedColor), [.rook, .queen].contains(mover.kind) else { return false }
    let backRank = matedColor == .white ? 1 : 8
    return king.rank.value == backRank
  }
}
