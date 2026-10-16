import ChessKit

/// Arrow and mark colors (green = solution, red = threat, blue = hint, yellow = user).
public enum AnnotationColor: String, Sendable, Codable, CaseIterable {
  case green, red, blue, yellow
}

public struct Arrow: Hashable, Sendable {
  public var from: Square
  public var to: Square
  public var color: AnnotationColor

  public init(from: Square, to: Square, color: AnnotationColor) {
    self.from = from
    self.to = to
    self.color = color
  }
}

/// Arrows and marks drawn over the board: the coach's (`arrows`) and the user's own.
public struct AnnotationLayer: Equatable, Sendable {
  public var arrows: [Arrow] = []
  public var circles: [Square: AnnotationColor] = [:]
  public private(set) var userArrows: [Arrow] = []
  public private(set) var userCircles: [Square] = []

  public init() {}

  /// Long-press drag: an arrow, or a circle when start == end. Drawing it again removes it.
  public mutating func toggleUserArrow(from: Square, to: Square) {
    if from == to {
      if let i = userCircles.firstIndex(of: from) { userCircles.remove(at: i) } else { userCircles.append(from) }
      return
    }
    let arrow = Arrow(from: from, to: to, color: .yellow)
    if let i = userArrows.firstIndex(of: arrow) { userArrows.remove(at: i) } else { userArrows.append(arrow) }
  }

  public mutating func clearUser() {
    userArrows = []
    userCircles = []
  }
}

/// Square tints derived from game state for a given ply.
public struct BoardHighlights: Equatable, Sendable {
  public var lastMove: [Square] = []
  public var check: Square?
  public var selected: Square?
  public var targets: [Square] = []
  public var premove: [Square] = []

  public init(lastMove: [Square] = [], check: Square? = nil, selected: Square? = nil, targets: [Square] = [], premove: [Square] = []) {
    self.lastMove = lastMove
    self.check = check
    self.selected = selected
    self.targets = targets
    self.premove = premove
  }

  public static func make(session: GameSession, ply: Int, interaction: BoardInteraction) -> BoardHighlights {
    var h = BoardHighlights()
    if ply > 0, ply <= session.history.count {
      let move = session.history[ply - 1].move
      h.lastMove = [move.start, move.end]
    }
    let atLatest = ply == session.history.count
    if atLatest {
      h.check = session.checkedKingSquare
      h.selected = interaction.selected
      h.targets = interaction.legalTargets
      if let p = interaction.premove { h.premove = [p.from, p.to] }
    } else if let position = Position(fen: session.fen(atPly: ply)) {
      h.check = BoardHighlights.checkedKing(in: position)
    }
    return h
  }

  static func checkedKing(in position: Position) -> Square? {
    switch Board(position: position).state {
    case .check(let color), .checkmate(let color):
      position.pieces.first { $0.kind == .king && $0.color == color }?.square
    default:
      nil
    }
  }
}
