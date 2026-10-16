import ChessKit
import Foundation

/// Named openings from lichess-org/chess-openings (CC0), keyed by position.
/// A move is "book" when the position it reaches is a known opening position.
public final class OpeningBook: Sendable {
  public struct Opening: Sendable, Equatable {
    public var eco: String
    public var name: String
  }

  /// FEN key (no counters) → the opening named exactly at that position.
  private let byPosition: [String: Opening]
  /// Every position on any listed line (all are "book").
  private let bookPositions: Set<String>

  public static let shared = OpeningBook()

  init(tsv: String? = nil) {
    let text = tsv ?? Bundle.module.url(forResource: "openings", withExtension: "tsv")
      .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    var map: [String: Opening] = [:]
    var book = Set<String>()
    for line in text.split(separator: "\n").dropFirst() {
      let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard cols.count >= 3 else { continue }
      let opening = Opening(eco: String(cols[0]), name: String(cols[1]))
      var position = Position.standard
      for token in cols[2].split(separator: " ") where !token.hasSuffix(".") {
        guard let move = Move(san: String(token), position: position) else { break }
        var board = Board(position: position)
        guard var made = board.move(pieceAt: move.start, to: move.end) else { break }
        if let promoted = move.promotedPiece {
          made = board.completePromotion(of: made, to: promoted.kind)
        }
        _ = made
        position = board.position
        book.insert(FENTools.key(position.fen))
      }
      map[FENTools.key(position.fen)] = opening
    }
    byPosition = map
    bookPositions = book
  }

  public var count: Int { byPosition.count }

  public func opening(atFEN fen: String) -> Opening? { byPosition[FENTools.key(fen)] }

  public func isBook(fenAfter: String) -> Bool { bookPositions.contains(FENTools.key(fenAfter)) }

  /// Deepest named opening along a game's positions.
  public func name(of session: GameSession) -> Opening? {
    (0...session.history.count).reversed().lazy.compactMap { self.opening(atFEN: session.fen(atPly: $0)) }.first
  }
}
