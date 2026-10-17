import ChessKit
import Foundation

/// Follows a coach game through the learner's repertoire: which line it's in, what comes
/// next, and the idea of each move.
public struct OpeningGuide: Sendable {
  public let repertoires: [Repertoire]

  /// The learner's repertoires (style + added) for their colour (Black has ones vs 1.e4 and vs 1.d4).
  public init(style: String, added: [String] = [], userColor: Piece.Color) {
    self.init(repertoires: RepertoireLibrary.mine(style: style, added: added).filter { $0.side == userColor })
  }

  init(repertoires: [Repertoire]) {
    self.repertoires = repertoires
  }

  /// Repertoires the game (UCI moves from the start) still follows, with the node reached
  /// (nil = no moves yet).
  public func follow(_ moves: [String]) -> [(repertoire: Repertoire, node: Int?)] {
    repertoires.compactMap { rep in
      guard rep.startFEN == GameSession.standardFEN else { return nil }
      var node: Int?
      for uci in moves {
        guard let next = rep.children(of: node).first(where: { $0.uci == uci }) else { return nil }
        node = next.id
      }
      return (rep, node)
    }
  }

  /// Book moves from here (either side's, whoever is to move).
  public func nextMoves(_ moves: [String]) -> [RepertoireNode] {
    follow(moves).flatMap { $0.repertoire.children(of: $0.node) }
  }

  /// The node for the last move played, when the game is still in book.
  public func lastNode(_ moves: [String]) -> RepertoireNode? {
    follow(moves).lazy.compactMap { f in f.node.map { f.repertoire.node($0) } }.first
  }

  /// The repertoire's name once only one fits the game.
  public func name(_ moves: [String]) -> String? {
    let reps = follow(moves)
    return reps.count == 1 ? reps[0].repertoire.name : nil
  }

  /// Repertoire summary once only one fits.
  public func summary(_ moves: [String]) -> String? {
    let reps = follow(moves)
    return reps.count == 1 ? reps[0].repertoire.summary : nil
  }
}
