import ChessKit
import Foundation

/// One move as it was played in a session.
public struct PlayedMove: Sendable, Equatable {
  public var move: Move
  public var san: String
  public var uci: String
  public var fenAfter: String
  /// Mover's remaining clock right after the move, if clocks are used.
  public var clockAfter: TimeInterval?

  public var color: Piece.Color { move.piece.color }
}

public enum Termination: String, Codable, Sendable {
  case checkmate, resignation, timeout, stalemate, repetition, fiftyMoves
  case insufficientMaterial, agreement, timeoutVsInsufficientMaterial, abandoned

  public var displayName: String {
    switch self {
    case .checkmate: "Checkmate"
    case .resignation: "Resignation"
    case .timeout: "Time"
    case .stalemate: "Stalemate"
    case .repetition: "Repetition"
    case .fiftyMoves: "50-move rule"
    case .insufficientMaterial: "Insufficient material"
    case .agreement: "Agreement"
    case .timeoutVsInsufficientMaterial: "Timeout vs insufficient material"
    case .abandoned: "Abandoned"
    }
  }
}

public struct GameResult: Sendable, Equatable {
  /// nil means a draw.
  public var winner: Piece.Color?
  public var termination: Termination

  public init(winner: Piece.Color?, termination: Termination) {
    self.winner = winner
    self.termination = termination
  }

  public var pgnResult: String {
    switch winner {
    case .white: "1-0"
    case .black: "0-1"
    case nil: "1/2-1/2"
    }
  }
}

public enum ApplyOutcome: Sendable, Equatable {
  case applied(PlayedMove)
  case needsPromotion
  case illegal
}

/// A game in progress: rules via chesskit `Board`, plus history, result and PGN export.
public struct GameSession: Sendable {
  public static let standardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  public let startFEN: String
  public private(set) var board: Board
  public internal(set) var history: [PlayedMove] = []
  public private(set) var result: GameResult?

  public init(startFEN: String = GameSession.standardFEN) {
    self.startFEN = startFEN
    board = Board(position: Position(fen: startFEN) ?? .standard)
    // chesskit's move-less Board(position:) judges the side NOT to move, so decide
    // the start position's result ourselves from the side to move.
    result = Self.initialResult(board.position, board: board)
  }

  static func initialResult(_ position: Position, board: Board) -> GameResult? {
    let side = position.sideToMove
    let hasMove = position.pieces.contains { $0.color == side && !board.legalMoves(forPieceAt: $0.square).isEmpty }
    if !hasMove {
      let map = BoardMap(position)
      let inCheck = map.king(of: side).map { !map.attackers(of: $0, by: side.opposite).isEmpty } ?? false
      return inCheck ? GameResult(winner: side.opposite, termination: .checkmate) : GameResult(winner: nil, termination: .stalemate)
    }
    if position.hasInsufficientMaterial { return GameResult(winner: nil, termination: .insufficientMaterial) }
    return nil
  }

  public var position: Position { board.position }
  public var sideToMove: Piece.Color { board.position.sideToMove }
  public var isOver: Bool { result != nil }
  public var lastMove: PlayedMove? { history.last }

  /// The king square in check, if the side to move is in check.
  public var checkedKingSquare: Square? {
    switch board.state {
    case .check(let color), .checkmate(let color):
      position.pieces.first { $0.kind == .king && $0.color == color }?.square
    default:
      nil
    }
  }

  public func legalTargets(from square: Square) -> [Square] {
    guard !isOver, let piece = position.piece(at: square), piece.color == sideToMove else { return [] }
    return board.legalMoves(forPieceAt: square)
  }

  /// Whether moving `from`→`to` is a legal pawn promotion (needs a piece choice).
  public func isPromotion(from: Square, to: Square) -> Bool {
    guard let piece = position.piece(at: from), piece.kind == .pawn else { return false }
    let lastRank = piece.color == .white ? 8 : 1
    return to.rank.value == lastRank && legalTargets(from: from).contains(to)
  }

  @discardableResult
  public mutating func apply(from: Square, to: Square, promotion: Piece.Kind? = nil) -> ApplyOutcome {
    guard legalTargets(from: from).contains(to) else { return .illegal }
    let promoting = isPromotion(from: from, to: to)
    if promoting && promotion == nil { return .needsPromotion }
    guard var move = board.move(pieceAt: from, to: to) else { return .illegal }
    if promoting, let kind = promotion {
      move = board.completePromotion(of: move, to: kind)
    }
    let played = PlayedMove(move: move, san: move.san, uci: Self.uci(of: move), fenAfter: position.fen)
    history.append(played)
    updateResultFromBoard()
    return .applied(played)
  }

  /// Applies an engine move like `e2e4` or `e7e8q`.
  @discardableResult
  public mutating func apply(uci: String) -> ApplyOutcome {
    guard let parsed = UCIMove(uci) else { return .illegal }
    return apply(from: parsed.from, to: parsed.to, promotion: parsed.promotion ?? (isPromotion(from: parsed.from, to: parsed.to) ? .queen : nil))
  }

  public mutating func setClockAfterLastMove(_ seconds: TimeInterval) {
    guard !history.isEmpty else { return }
    history[history.count - 1].clockAfter = seconds
  }

  public mutating func resign(_ color: Piece.Color) {
    guard !isOver else { return }
    result = GameResult(winner: color.opposite, termination: .resignation)
  }

  public mutating func agreeDraw() {
    guard !isOver else { return }
    result = GameResult(winner: nil, termination: .agreement)
  }

  /// `color` ran out of time. A draw if the opponent cannot possibly mate.
  public mutating func flag(_ color: Piece.Color) {
    guard !isOver else { return }
    if Self.cannotMate(position.pieces.filter { $0.color == color.opposite }) {
      result = GameResult(winner: nil, termination: .timeoutVsInsufficientMaterial)
    } else {
      result = GameResult(winner: color.opposite, termination: .timeout)
    }
  }

  /// FEN after `ply` half-moves (0 = start).
  public func fen(atPly ply: Int) -> String {
    ply <= 0 ? startFEN : history[min(ply, history.count) - 1].fenAfter
  }

  /// Pieces `color` has captured, in capture order.
  public func captured(by color: Piece.Color) -> [Piece] {
    history.compactMap { played in
      guard played.color == color, case .capture(let piece) = played.move.result else { return nil }
      return piece
    }
  }

  /// White's material minus Black's (pawn 1, minor 3, rook 5, queen 9).
  public var materialBalance: Int {
    position.pieces.reduce(0) { sum, piece in
      sum + (piece.color == .white ? 1 : -1) * Self.value(of: piece.kind)
    }
  }

  public static func value(of kind: Piece.Kind) -> Int {
    switch kind {
    case .pawn: 1
    case .knight, .bishop: 3
    case .rook: 5
    case .queen: 9
    case .king: 0
    }
  }

  /// PGN with tags, SAN moves, `%clk` comments and the result token.
  public func pgn(tags: [String: String]) -> String {
    let order = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
    var allTags = tags
    allTags["Result"] = result?.pgnResult ?? "*"
    if startFEN != Self.standardFEN {
      allTags["SetUp"] = "1"
      allTags["FEN"] = startFEN
    }
    let sortedKeys = order.filter { allTags[$0] != nil } + allTags.keys.filter { !order.contains($0) }.sorted()
    func escape(_ v: String) -> String { v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    var lines = sortedKeys.map { "[\($0) \"\(escape(allTags[$0]!))\"]" }
    lines.append("")

    let startsWithBlack = (Position(fen: startFEN)?.sideToMove ?? .white) == .black
    let startMoveNumber = Int(startFEN.split(separator: " ").last ?? "1") ?? 1
    var tokens: [String] = []
    for (index, played) in history.enumerated() {
      let plyIndex = index + (startsWithBlack ? 1 : 0)
      let moveNumber = startMoveNumber + plyIndex / 2
      if plyIndex.isMultiple(of: 2) {
        tokens.append("\(moveNumber).")
      } else if index == 0 {
        tokens.append("\(moveNumber)...")
      }
      tokens.append(played.san)
      if let clock = played.clockAfter {
        tokens.append("{[%clk \(Self.clockString(clock))]}")
      }
    }
    tokens.append(result?.pgnResult ?? "*")
    lines.append(tokens.joined(separator: " "))
    return lines.joined(separator: "\n")
  }

  // MARK: - Private

  private mutating func updateResultFromBoard() {
    switch board.state {
    case .checkmate(let color):
      result = GameResult(winner: color.opposite, termination: .checkmate)
    case .draw(let reason):
      let termination: Termination =
        switch reason {
        case .stalemate: .stalemate
        case .repetition: .repetition
        case .fiftyMoves: .fiftyMoves
        case .insufficientMaterial: .insufficientMaterial
        case .agreement: .agreement
        }
      result = GameResult(winner: nil, termination: termination)
    default:
      break
    }
  }

  static func uci(of move: Move) -> String {
    var text = move.start.notation + move.end.notation
    if let promoted = move.promotedPiece {
      text += promoted.kind.notation.lowercased()
    }
    return text
  }

  /// A lone king, or king + one minor piece, cannot force mate.
  static func cannotMate(_ pieces: [Piece]) -> Bool {
    let nonKing = pieces.filter { $0.kind != .king }
    if nonKing.isEmpty { return true }
    return nonKing.count == 1 && (nonKing[0].kind == .bishop || nonKing[0].kind == .knight)
  }

  static func clockString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
  }
}

/// A parsed UCI move string.
public struct UCIMove: Sendable, Equatable {
  public var from: Square
  public var to: Square
  public var promotion: Piece.Kind?

  public init?(_ text: String) {
    guard text.count == 4 || text.count == 5 else { return nil }
    let chars = Array(text)
    let fromText = String(chars[0...1])
    let toText = String(chars[2...3])
    guard Self.isSquare(fromText), Self.isSquare(toText) else { return nil }
    from = Square(fromText)
    to = Square(toText)
    if chars.count == 5 {
      switch chars[4] {
      case "q": promotion = .queen
      case "r": promotion = .rook
      case "b": promotion = .bishop
      case "n": promotion = .knight
      default: return nil
      }
    }
  }

  static func isSquare(_ text: String) -> Bool {
    let c = Array(text)
    return c.count == 2 && ("a"..."h").contains(String(c[0])) && ("1"..."8").contains(String(c[1]))
  }
}
