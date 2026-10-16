import ChessKit
import CoreGraphics
import Foundation

/// Maps between board squares and points for a square board of side `size`.
public struct BoardGeometry: Sendable, Equatable {
  public var size: CGFloat
  public var flipped: Bool

  public init(size: CGFloat, flipped: Bool) {
    self.size = size
    self.flipped = flipped
  }

  public var squareSize: CGFloat { size / 8 }

  /// Column 0…7 left→right and row 0…7 top→bottom as drawn.
  public func cell(of square: Square) -> (column: Int, row: Int) {
    let file = square.file.number - 1
    let rank = square.rank.value - 1
    return flipped ? (7 - file, rank) : (file, 7 - rank)
  }

  public func square(column: Int, row: Int) -> Square {
    let file = flipped ? 7 - column : column
    let rank = flipped ? row : 7 - row
    return Square("\(Square.File(file + 1).rawValue)\(rank + 1)")
  }

  public func origin(of square: Square) -> CGPoint {
    let c = cell(of: square)
    return CGPoint(x: CGFloat(c.column) * squareSize, y: CGFloat(c.row) * squareSize)
  }

  public func center(of square: Square) -> CGPoint {
    let o = origin(of: square)
    return CGPoint(x: o.x + squareSize / 2, y: o.y + squareSize / 2)
  }

  /// The square under `point`, or nil when outside the board.
  public func square(at point: CGPoint) -> Square? {
    guard point.x >= 0, point.y >= 0, point.x < size, point.y < size else { return nil }
    return square(column: Int(point.x / squareSize), row: Int(point.y / squareSize))
  }

  public static func isLightSquare(_ square: Square) -> Bool {
    (square.file.number + square.rank.value).isMultiple(of: 2) == false
  }
}

/// A piece with a stable identity so the view can slide it between squares.
public struct IdentifiedPiece: Identifiable, Equatable, Sendable {
  public var id: Int
  public var piece: Piece
}

/// Keeps piece identities stable across position changes: a piece that left one
/// square and the same kind/color that appeared elsewhere keep the same id
/// (so moves animate as slides, captures fade out, promotions swap).
public enum PieceIdentity {
  public static func reconcile(previous: [IdentifiedPiece], next pieces: [Piece], nextID: inout Int) -> [IdentifiedPiece] {
    var result: [IdentifiedPiece] = []
    var unmatchedOld = previous
    var unmatchedNew: [Piece] = []

    // 1. Pieces that did not move keep their id.
    for piece in pieces {
      if let i = unmatchedOld.firstIndex(where: { $0.piece == piece }) {
        result.append(IdentifiedPiece(id: unmatchedOld[i].id, piece: piece))
        unmatchedOld.remove(at: i)
      } else {
        unmatchedNew.append(piece)
      }
    }
    // 2. Moved pieces: match same kind+color, nearest first.
    for piece in unmatchedNew {
      let candidates = unmatchedOld.enumerated().filter { $0.element.piece.kind == piece.kind && $0.element.piece.color == piece.color }
      if let best = candidates.min(by: { distance($0.element.piece.square, piece.square) < distance($1.element.piece.square, piece.square) }) {
        result.append(IdentifiedPiece(id: best.element.id, piece: piece))
        unmatchedOld.remove(at: best.offset)
      } else {
        result.append(IdentifiedPiece(id: nextID, piece: piece))
        nextID += 1
      }
    }
    return result
  }

  static func distance(_ a: Square, _ b: Square) -> Int {
    abs(a.file.number - b.file.number) + abs(a.rank.value - b.rank.value)
  }
}
