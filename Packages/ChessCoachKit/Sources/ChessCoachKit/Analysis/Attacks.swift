import ChessKit

/// A mutable square → piece map with attack geometry (pseudo-legal; pins ignored,
/// which is what tactics detection wants).
public struct BoardMap: Sendable, Equatable {
  public private(set) var pieces: [Square: Piece]

  public init(_ position: Position) {
    var map: [Square: Piece] = [:]
    for piece in position.pieces { map[piece.square] = piece }
    pieces = map
  }

  public subscript(_ square: Square) -> Piece? { pieces[square] }

  public mutating func remove(_ square: Square) { pieces[square] = nil }

  public mutating func move(from: Square, to: Square) {
    guard var piece = pieces[from] else { return }
    pieces[from] = nil
    piece.square = to
    pieces[to] = piece
  }

  public func pieces(of color: Piece.Color) -> [Piece] { pieces.values.filter { $0.color == color } }

  public func king(of color: Piece.Color) -> Square? {
    pieces.values.first { $0.kind == .king && $0.color == color }?.square
  }

  /// Squares `piece` attacks (captures it could make if an enemy stood there).
  public func attacks(of piece: Piece) -> [Square] {
    let (f, r) = (piece.square.file.number, piece.square.rank.value)
    switch piece.kind {
    case .pawn:
      let dir = piece.color == .white ? 1 : -1
      return [(-1, dir), (1, dir)].compactMap { Self.square(f + $0.0, r + $0.1) }
    case .knight:
      return [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)].compactMap { Self.square(f + $0.0, r + $0.1) }
    case .king:
      return [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)].compactMap { Self.square(f + $0.0, r + $0.1) }
    case .bishop:
      return slide(from: piece.square, directions: Self.diagonals)
    case .rook:
      return slide(from: piece.square, directions: Self.orthogonals)
    case .queen:
      return slide(from: piece.square, directions: Self.diagonals + Self.orthogonals)
    }
  }

  public func attackers(of target: Square, by color: Piece.Color) -> [Piece] {
    pieces(of: color).filter { attacks(of: $0).contains(target) }
  }

  /// Rays for sliders: squares in `direction` until (and including) the first piece.
  public func ray(from square: Square, direction: (Int, Int)) -> [Square] {
    var result: [Square] = []
    var (f, r) = (square.file.number + direction.0, square.rank.value + direction.1)
    while let s = Self.square(f, r) {
      result.append(s)
      if pieces[s] != nil { break }
      f += direction.0
      r += direction.1
    }
    return result
  }

  func slide(from square: Square, directions: [(Int, Int)]) -> [Square] {
    directions.flatMap { ray(from: square, direction: $0) }
  }

  static let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
  static let orthogonals = [(1, 0), (-1, 0), (0, 1), (0, -1)]

  static func directions(for kind: Piece.Kind) -> [(Int, Int)] {
    switch kind {
    case .bishop: diagonals
    case .rook: orthogonals
    case .queen: diagonals + orthogonals
    default: []
    }
  }

  static func square(_ file: Int, _ rank: Int) -> Square? {
    guard (1...8).contains(file), (1...8).contains(rank) else { return nil }
    return Square("\(Square.File(file).rawValue)\(rank)")
  }
}

/// Piece values used for tactics (king large so it always counts as a target).
public enum PieceValue {
  public static func of(_ kind: Piece.Kind) -> Int {
    switch kind {
    case .pawn: 1
    case .knight, .bishop: 3
    case .rook: 5
    case .queen: 9
    case .king: 100
    }
  }
}

public enum StaticExchange {
  /// Material `color` nets by starting a capture sequence on `square` (≥ 0 means
  /// the capture is at least even). Each side recaptures with its least valuable
  /// attacker and may stop when continuing would lose.
  public static func evaluate(_ map: BoardMap, square: Square, by color: Piece.Color) -> Int {
    guard let target = map[square], target.color != color else { return 0 }
    var board = map
    var gains: [Int] = []
    var side = color
    var onSquare = PieceValue.of(target.kind)
    while let attacker = board.attackers(of: square, by: side).min(by: { PieceValue.of($0.kind) < PieceValue.of($1.kind) }) {
      gains.append(onSquare)
      onSquare = PieceValue.of(attacker.kind)
      board.remove(square)
      board.move(from: attacker.square, to: square)
      side = side.opposite
      if attacker.kind == .king, !board.attackers(of: square, by: side).isEmpty {
        // King can't capture into a defended square.
        gains.removeLast()
        break
      }
    }
    guard !gains.isEmpty else { return 0 }
    // Negamax back-propagation: each side may decline to continue.
    var value = 0
    for gain in gains.reversed() {
      value = max(0, gain - value)
    }
    return value
  }
}
