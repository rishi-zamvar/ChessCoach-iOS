import ChessKit
import Foundation

/// One move in a repertoire tree.
public struct RepertoireNode: Identifiable, Equatable, Sendable {
  public let id: Int
  public let parent: Int?
  public let san: String
  public let uci: String
  public let fenAfter: String
  /// The idea of the move (comment text with annotation commands removed).
  public var idea: String
  public var arrows: [Arrow]
  public var highlights: [Square: AnnotationColor]
  /// The opponent's common deviation (a branch worth pausing on).
  public var isDeviation: Bool
  /// Name of a trap this move springs or falls into.
  public var trap: String?
  public var children: [Int]
  /// Ply depth (1 = first move).
  public let ply: Int
}

/// An annotated opening repertoire parsed from PGN (see Resources/repertoires).
public struct Repertoire: Identifiable, Sendable {
  public var id: String { fileName }
  public let fileName: String
  public let name: String
  public let summary: String
  public let style: String
  /// The side the learner plays.
  public let side: Piece.Color
  public let startFEN: String
  public private(set) var nodes: [RepertoireNode]
  /// Root-level moves (children of the start position).
  public private(set) var roots: [Int]

  public init(pgn: String, fileName: String) throws {
    self.fileName = fileName
    let tags = Self.tags(in: pgn)
    name = tags["Name"] ?? tags["Event"] ?? fileName
    summary = tags["Summary"] ?? ""
    style = tags["Style"] ?? ""
    side = tags["Side"]?.lowercased() == "black" ? .black : .white
    startFEN = tags["FEN"] ?? GameSession.standardFEN
    nodes = []
    roots = []
    try parse(movetext: Self.movetext(of: pgn))
  }

  public func node(_ id: Int) -> RepertoireNode { nodes[id] }
  public func children(of id: Int?) -> [RepertoireNode] { (id.map { nodes[$0].children } ?? roots).map { nodes[$0] } }

  /// FEN before `node`'s move.
  public func fenBefore(_ node: RepertoireNode) -> String {
    node.parent.map { nodes[$0].fenAfter } ?? startFEN
  }

  /// Moves from the start to `id` (inclusive).
  public func path(to id: Int) -> [RepertoireNode] {
    var result: [RepertoireNode] = []
    var current: Int? = id
    while let c = current {
      result.append(nodes[c])
      current = nodes[c].parent
    }
    return result.reversed()
  }

  /// Every root-to-leaf line, main line first (Learn mode chapters).
  public var lines: [[RepertoireNode]] {
    var result: [[RepertoireNode]] = []
    func walk(_ id: Int, _ acc: [RepertoireNode]) {
      let node = nodes[id]
      let next = acc + [node]
      if node.children.isEmpty { result.append(next) } else { node.children.forEach { walk($0, next) } }
    }
    roots.forEach { walk($0, []) }
    return result
  }

  public var trapCount: Int { nodes.filter { $0.trap != nil }.count }

  /// Whose move `node` is.
  public func mover(of node: RepertoireNode) -> Piece.Color {
    let first = Position(fen: startFEN)?.sideToMove ?? .white
    return node.ply % 2 == 1 ? first : first.opposite
  }

  // MARK: - Game comparison

  public enum Departure: Equatable, Sendable {
    /// The learner played something else at `ply`; `expected` lists repertoire moves.
    case userLeft(ply: Int, played: String, expected: [String])
    /// The opponent left the book at `ply` (the learner may want to add this branch).
    case opponentLeft(ply: Int, played: String)
    /// The game followed the repertoire to its end.
    case followedToEnd(ply: Int)
  }

  /// Where a game (UCI moves from the standard start) left this repertoire.
  public func departure(gameMoves: [String], userColor: Piece.Color) -> Departure? {
    guard userColor == side else { return nil }
    var options = roots
    var session = GameSession(startFEN: startFEN)
    for (index, uci) in gameMoves.enumerated() {
      if options.isEmpty { return .followedToEnd(ply: index) }
      let moverIsUser = session.sideToMove == side
      guard case .applied(let played) = session.apply(uci: uci) else { return nil }
      if let match = options.first(where: { nodes[$0].uci == played.uci }) {
        options = nodes[match].children
        continue
      }
      return moverIsUser
        ? .userLeft(ply: index + 1, played: played.san, expected: options.map { nodes[$0].san })
        : .opponentLeft(ply: index + 1, played: played.san)
    }
    return options.isEmpty ? .followedToEnd(ply: gameMoves.count) : nil
  }

  // MARK: - Parsing

  static func tags(in pgn: String) -> [String: String] {
    var tags: [String: String] = [:]
    let regex = try? NSRegularExpression(pattern: #"\[(\w+)\s+"((?:[^"\\]|\\.)*)"\]"#)
    let range = NSRange(pgn.startIndex..., in: pgn)
    regex?.enumerateMatches(in: pgn, range: range) { match, _, _ in
      guard let m = match, let k = Range(m.range(at: 1), in: pgn), let v = Range(m.range(at: 2), in: pgn) else { return }
      tags[String(pgn[k])] = String(pgn[v])
    }
    return tags
  }

  static func movetext(of pgn: String) -> String {
    pgn.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
      .joined(separator: "\n")
  }

  enum Token: Equatable {
    case move(String), comment(String), open, close
  }

  static func tokenize(_ text: String) -> [Token] {
    var tokens: [Token] = []
    var i = text.startIndex
    while i < text.endIndex {
      let c = text[i]
      if c == "{" {
        let end = text[i...].firstIndex(of: "}") ?? text.endIndex
        tokens.append(.comment(String(text[text.index(after: i)..<end])))
        i = end < text.endIndex ? text.index(after: end) : end
      } else if c == "(" {
        tokens.append(.open)
        i = text.index(after: i)
      } else if c == ")" {
        tokens.append(.close)
        i = text.index(after: i)
      } else if c.isWhitespace {
        i = text.index(after: i)
      } else {
        var j = i
        while j < text.endIndex, !text[j].isWhitespace, !"{}()".contains(text[j]) { j = text.index(after: j) }
        let word = String(text[i..<j])
        i = j
        // Skip move numbers ("12." / "12..."), NAGs, results.
        if word.first == "$" || ["*", "1-0", "0-1", "1/2-1/2"].contains(word) { continue }
        let stripped = word.replacingOccurrences(of: #"^\d+\.+"#, with: "", options: .regularExpression)
        if stripped.isEmpty { continue }
        tokens.append(.move(stripped.trimmingCharacters(in: CharacterSet(charactersIn: "!?"))))
      }
    }
    return tokens
  }

  public enum ParseError: Error, Equatable {
    case illegalMove(String, ply: Int)
    case unbalancedVariation
  }

  mutating func parse(movetext: String) throws {
    var current: Int? = nil  // node whose position we're at (nil = start)
    var stack: [Int?] = []
    for token in Self.tokenize(movetext) {
      switch token {
      case .move(let san):
        current = try addMove(san: san, after: current)
      case .comment(let text):
        if let c = current { annotate(c, with: text) }
      case .open:
        stack.append(current)
        current = current.flatMap { nodes[$0].parent }
      case .close:
        guard let restored = stack.popLast() else { throw ParseError.unbalancedVariation }
        current = restored
      }
    }
    guard stack.isEmpty else { throw ParseError.unbalancedVariation }
  }

  mutating func addMove(san: String, after parent: Int?) throws -> Int {
    let fen = parent.map { nodes[$0].fenAfter } ?? startFEN
    let ply = (parent.map { nodes[$0].ply } ?? 0) + 1
    guard let position = Position(fen: fen), let move = Move(san: san, position: position) else {
      throw ParseError.illegalMove(san, ply: ply)
    }
    var session = GameSession(startFEN: fen)
    guard case .applied(let played) = session.apply(from: move.start, to: move.end, promotion: move.promotedPiece?.kind)
    else { throw ParseError.illegalMove(san, ply: ply) }
    let siblings = parent.map { nodes[$0].children } ?? roots
    if let existing = siblings.first(where: { nodes[$0].uci == played.uci }) { return existing }
    let id = nodes.count
    nodes.append(
      RepertoireNode(
        id: id, parent: parent, san: played.san, uci: played.uci, fenAfter: session.position.fen, idea: "",
        arrows: [], highlights: [:], isDeviation: false, trap: nil, children: [], ply: ply))
    if let parent { nodes[parent].children.append(id) } else { roots.append(id) }
    return id
  }

  mutating func annotate(_ id: Int, with comment: String) {
    var text = comment
    for command in Self.commands(in: comment) {
      switch command.name {
      case "cal":
        for spec in command.args.split(separator: ",") {
          let s = Array(spec.trimmingCharacters(in: .whitespaces))
          guard s.count == 5, let color = Self.color(s[0]) else { continue }
          let from = String(s[1...2]), to = String(s[3...4])
          if UCIMove.isSquare(from), UCIMove.isSquare(to) {
            nodes[id].arrows.append(Arrow(from: Square(from), to: Square(to), color: color))
          }
        }
      case "csl":
        for spec in command.args.split(separator: ",") {
          let s = Array(spec.trimmingCharacters(in: .whitespaces))
          guard s.count == 3, let color = Self.color(s[0]), UCIMove.isSquare(String(s[1...2])) else { continue }
          nodes[id].highlights[Square(String(s[1...2]))] = color
        }
      case "dev": nodes[id].isDeviation = true
      case "trap": nodes[id].trap = command.args.isEmpty ? "Trap" : command.args
      default: break
      }
      text = text.replacingOccurrences(of: command.raw, with: "")
    }
    let cleaned = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    nodes[id].idea = nodes[id].idea.isEmpty ? cleaned : nodes[id].idea + " " + cleaned
  }

  struct Command {
    var raw: String
    var name: String
    var args: String
  }

  static func commands(in comment: String) -> [Command] {
    guard let regex = try? NSRegularExpression(pattern: #"\[%(\w+)\s*([^\]]*)\]"#) else { return [] }
    let range = NSRange(comment.startIndex..., in: comment)
    return regex.matches(in: comment, range: range).compactMap { m in
      guard let r = Range(m.range, in: comment), let n = Range(m.range(at: 1), in: comment), let a = Range(m.range(at: 2), in: comment)
      else { return nil }
      return Command(raw: String(comment[r]), name: String(comment[n]), args: comment[a].trimmingCharacters(in: .whitespaces))
    }
  }

  static func color(_ c: Character) -> AnnotationColor? {
    switch c {
    case "G": .green
    case "R": .red
    case "B": .blue
    case "Y": .yellow
    default: nil
    }
  }
}

/// Bundled repertoires (Resources/repertoires/*.pgn).
public enum RepertoireLibrary {
  public static func all() -> [Repertoire] { all(bundle: .module) }

  static func all(bundle: Bundle) -> [Repertoire] {
    let urls = bundle.urls(forResourcesWithExtension: "pgn", subdirectory: "repertoires") ?? []
    return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
      return try? Repertoire(pgn: text, fileName: url.deletingPathExtension().lastPathComponent)
    }
  }

  /// The learner's repertoires for a style (white + black vs e4 + black vs d4).
  public static func forStyle(_ style: String) -> [Repertoire] {
    all().filter { $0.fileName.hasPrefix(style + "-") }
  }
}
