import ChessKit

/// What a tap or drop on the board should do.
public enum InteractionResult: Equatable, Sendable {
  case selected(Square)
  case deselected
  case move(from: Square, to: Square)
  case premoveQueued(from: Square, to: Square)
  case premoveCancelled
  case none
}

public struct Premove: Equatable, Sendable {
  public var from: Square
  public var to: Square
}

/// Pure tap/drag/premove state for the board. The view feeds it gestures; the
/// controller acts on the returned `InteractionResult`.
public struct BoardInteraction: Equatable, Sendable {
  public private(set) var selected: Square?
  public private(set) var legalTargets: [Square] = []
  public private(set) var dragging: Square?
  public private(set) var premove: Premove?

  public init() {}

  @discardableResult
  public mutating func tap(_ square: Square, session: GameSession, userColor: Piece.Color) -> InteractionResult {
    guard !session.isOver else { return .none }
    let userTurn = session.sideToMove == userColor

    if let from = selected {
      if from == square {
        clearSelection()
        return .deselected
      }
      if legalTargets.contains(square) {
        clearSelection()
        if userTurn { return .move(from: from, to: square) }
        premove = Premove(from: from, to: square)
        return .premoveQueued(from: from, to: square)
      }
    }
    if let piece = session.position.piece(at: square), piece.color == userColor {
      select(square, session: session, userColor: userColor)
      return .selected(square)
    }
    if premove != nil && !userTurn {
      premove = nil
      clearSelection()
      return .premoveCancelled
    }
    if selected != nil {
      clearSelection()
      return .deselected
    }
    return .none
  }

  /// Returns whether a drag may start on `square` (user's own piece).
  @discardableResult
  public mutating func dragBegan(at square: Square, session: GameSession, userColor: Piece.Color) -> Bool {
    guard !session.isOver, let piece = session.position.piece(at: square), piece.color == userColor else {
      return false
    }
    select(square, session: session, userColor: userColor)
    dragging = square
    return true
  }

  @discardableResult
  public mutating func dragEnded(at square: Square?, session: GameSession, userColor: Piece.Color) -> InteractionResult {
    guard let from = dragging else { return .none }
    dragging = nil
    guard let square, square != from, legalTargets.contains(square) else { return .none }
    clearSelection()
    if session.sideToMove == userColor { return .move(from: from, to: square) }
    premove = Premove(from: from, to: square)
    return .premoveQueued(from: from, to: square)
  }

  public mutating func dragCancelled() {
    dragging = nil
  }

  /// Takes the queued premove (the controller tries to play it).
  public mutating func takePremove() -> Premove? {
    defer { premove = nil }
    return premove
  }

  public mutating func reset() {
    self = BoardInteraction()
  }

  // MARK: - Private

  private mutating func select(_ square: Square, session: GameSession, userColor: Piece.Color) {
    selected = square
    legalTargets =
      session.sideToMove == userColor
      ? session.legalTargets(from: square)
      : Self.premoveTargets(from: square, session: session)
  }

  private mutating func clearSelection() {
    selected = nil
    legalTargets = []
  }

  /// Premove candidates: every square the piece attacks (including squares its own
  /// pieces stand on now, for recaptures) plus pawn pushes. Legality is checked when
  /// the premove is played.
  static func premoveTargets(from square: Square, session: GameSession) -> [Square] {
    let map = BoardMap(session.position)
    guard let piece = map[square] else { return [] }
    var targets = Set(map.attacks(of: piece))
    if piece.kind == .pawn {
      let dir = piece.color == .white ? 1 : -1
      let file = square.file.number
      let rank = square.rank.value
      if let one = BoardMap.square(file, rank + dir) { targets.insert(one) }
      let homeRank = piece.color == .white ? 2 : 7
      if rank == homeRank, let two = BoardMap.square(file, rank + 2 * dir) { targets.insert(two) }
    } else if piece.kind == .king {
      // Castling premoves.
      let back = piece.color == .white ? 1 : 8
      if rank(square) == back, square.file == .e {
        [BoardMap.square(7, back), BoardMap.square(3, back)].compactMap { $0 }.forEach { targets.insert($0) }
      }
    }
    targets.remove(square)
    return targets.sorted { $0.rawValue < $1.rawValue }
  }

  private static func rank(_ square: Square) -> Int { square.rank.value }
}
