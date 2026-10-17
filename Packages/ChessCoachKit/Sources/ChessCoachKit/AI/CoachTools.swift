import ChessKit
import Foundation

/// The board tools Claude can call (executed on the phone). Same names/shapes the PC's
/// MCP server will expose later.
public struct CoachTools: Sendable {
  let host: EngineHost?
  let profile: @Sendable () -> String

  public init(host: EngineHost?, profile: @escaping @Sendable () -> String) {
    self.host = host
    self.profile = profile
  }

  static func schema(_ properties: [String: JSON], required: [String]) -> JSON {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "required": .array(required.map(JSON.string)), "additionalProperties": .bool(false),
    ])
  }

  public static let definitions: [AITool] = [
    AITool(
      name: "get_position", description: "The current position: FEN, side to move, material, opening name, recent moves.",
      inputSchema: schema([:], required: [])),
    AITool(
      name: "legal_moves", description: "All legal moves for the side to move, in SAN.", inputSchema: schema([:], required: [])),
    AITool(
      name: "evaluate_moves",
      description: "Stockfish evaluation: the top lines (SAN) with the side-to-move's winning chances in percent. Use before claiming a move is good or bad.",
      inputSchema: schema([:], required: [])),
    AITool(
      name: "human_moves",
      description: "How likely a human around 1100 rating is to play each move here (Maia), top moves in SAN with percent.",
      inputSchema: schema([:], required: [])),
    AITool(
      name: "position_facts",
      description: "Deterministic tactics facts: hanging pieces for both sides, and checks/captures available.",
      inputSchema: schema([:], required: [])),
    AITool(
      name: "player_profile", description: "The learner's level, style and current weaknesses.", inputSchema: schema([:], required: [])),
    AITool(
      name: "draw",
      description: "Draw arrows on the learner's board. Colors: green = good move/plan, red = threat, blue = idea.",
      inputSchema: schema(
        [
          "arrows": .object([
            "type": .string("array"),
            "items": schema(
              [
                "from": .object(["type": .string("string")]), "to": .object(["type": .string("string")]),
                "color": .object(["type": .string("string"), "enum": .array(["green", "red", "blue"].map(JSON.string))]),
              ], required: ["from", "to", "color"]),
          ])
        ], required: ["arrows"])),
  ]

  /// Runs one tool for `fen`. Returns (text, isError); vocabulary collects every SAN/square
  /// the tools revealed (used to validate the final answer).
  public func execute(_ name: String, input: JSON, fen: String, history: [String], vocabulary: inout Set<String>, arrows: inout [Arrow]) async -> (String, Bool) {
    let session = GameSession(startFEN: fen)
    let position = session.position
    func sans(_ ucis: [String]) -> [String] { FactExtractor.sanLine(fen: fen, ucis: ucis) }
    switch name {
    case "get_position":
      let opening = OpeningBook.shared.opening(atFEN: fen)?.name
      let balance = session.materialBalance
      vocabulary.formUnion(history.suffix(8))
      return (
        JSON.object([
          "fen": .string(fen), "side_to_move": .string(position.sideToMove == .white ? "white" : "black"),
          "material_white_minus_black": .number(Double(balance)), "opening": opening.map(JSON.string) ?? .null,
          "recent_moves_san": .array(history.suffix(8).map(JSON.string)),
        ]).text, false)
    case "legal_moves":
      var moves: [String] = []
      for piece in position.pieces where piece.color == position.sideToMove {
        for target in session.legalTargets(from: piece.square) {
          var copy = session
          if case .applied(let played) = copy.apply(from: piece.square, to: target, promotion: copy.isPromotion(from: piece.square, to: target) ? .queen : nil) {
            moves.append(played.san)
          }
        }
      }
      vocabulary.formUnion(moves)
      return (JSON.array(moves.sorted().map(JSON.string)).text, false)
    case "evaluate_moves":
      guard let host, let result = try? await host.search(.stockfish, fen: fen, limit: .depth(12), multipv: 3) else {
        return ("Engine unavailable.", true)
      }
      let lines: [JSON] = result.lines.map { line in
        let san = sans(Array(line.pv.prefix(5)))
        vocabulary.formUnion(san)
        return .object(["line": .array(san.map(JSON.string)), "win_percent": .number(WinChance.winPercent(line.score).rounded())])
      }
      return (JSON.array(lines).text, false)
    case "human_moves":
      guard let host, let result = try? await host.search(.maia(rating: 1100), fen: fen, limit: .nodes(1)) else {
        return ("Maia unavailable.", true)
      }
      let top = result.policy.sorted { $0.value > $1.value }.prefix(5)
      let out: [JSON] = top.compactMap { uci, p in
        guard let san = sans([uci]).first else { return nil }
        vocabulary.insert(san)
        return .object(["move": .string(san), "percent": .number((p * 100).rounded())])
      }
      return (JSON.array(out).text, false)
    case "position_facts":
      let mine = FactExtractor.hangingPieces(fen: fen, of: position.sideToMove)
      let theirs = FactExtractor.hangingPieces(fen: fen, of: position.sideToMove.opposite)
      let cc = BoardVision.checksAndCaptures(fen: fen).compactMap { sans([$0]).first }
      vocabulary.formUnion(cc)
      for p in mine + theirs { vocabulary.insert(p.square.notation) }
      func describe(_ ps: [Piece]) -> JSON { .array(ps.map { .string("\(FactExtractor.name(of: $0.kind)) on \($0.square.notation)") }) }
      return (
        JSON.object([
          "side_to_move_loose_pieces": describe(mine), "opponent_loose_pieces": describe(theirs),
          "checks_and_captures": .array(cc.map(JSON.string)),
        ]).text, false)
    case "player_profile":
      return (profile(), false)
    case "draw":
      for a in input["arrows"]?.arrayValue ?? [] {
        guard let from = a["from"]?.stringValue, let to = a["to"]?.stringValue, UCIMove.isSquare(from), UCIMove.isSquare(to),
          let color = AnnotationColor(rawValue: a["color"]?.stringValue ?? "")
        else { continue }
        arrows.append(Arrow(from: Square(from), to: Square(to), color: color))
        vocabulary.formUnion([from, to])
      }
      return ("Drawn.", false)
    default:
      return ("Unknown tool \(name).", true)
    }
  }
}

/// "Ask the coach" about a position: Claude answers using the board tools; the answer
/// may only name moves/squares the tools (or the visible move list) produced.
public struct AskCoach: Sendable {
  let client: LLMClient
  let tools: CoachTools

  public init(client: LLMClient, tools: CoachTools) {
    self.client = client
    self.tools = tools
  }

  public struct Answer: Sendable, Equatable {
    public var text: String
    public var arrows: [Arrow]
    public var grounded: Bool
  }

  static let system = """
    You are a friendly chess coach in a phone app, talking to a beginner (around 300–600). Answer their question about the \
    position on their board in 2–4 short sentences of plain English.
    Always check facts with the tools before stating them: use evaluate_moves before calling a move good or bad, \
    position_facts for what is loose or attacked, legal_moves before suggesting a move. Never guess a move.
    Only mention moves (SAN) and squares that the tools returned. Use draw to put 1–3 arrows on the board when it helps.
    Teach the idea and a habit, not just the move. No markdown, lists, or engine numbers.
    """

  public func ask(_ question: String, fen: String, history: [String]) async throws -> Answer {
    var vocabulary = Set(history.suffix(8))
    var arrows: [Arrow] = []
    let box = ToolBox(tools: tools, fen: fen, history: history)
    let (text, _) = try await client.runTools(
      tier: .smart, system: Self.system, user: question, tools: CoachTools.definitions, maxTurns: 6,
      effort: "low", purpose: "ask-coach"
    ) { name, input in await box.run(name, input) }
    vocabulary.formUnion(await box.vocabulary)
    arrows = await box.arrows
    let squares = Set(vocabulary.flatMap { Explainer.mentions(in: $0).compactMap { Explainer.squareSuffix($0) } })
    let grounded = Explainer.mentions(in: text).allSatisfy { token in
      vocabulary.contains(token) || squares.contains(Explainer.squareSuffix(token) ?? token)
    }
    return Answer(text: text.trimmingCharacters(in: .whitespacesAndNewlines), arrows: arrows, grounded: grounded)
  }
}

/// Holds tool state across the async loop.
actor ToolBox {
  let tools: CoachTools
  let fen: String
  let history: [String]
  var vocabulary: Set<String> = []
  var arrows: [Arrow] = []

  init(tools: CoachTools, fen: String, history: [String]) {
    self.tools = tools
    self.fen = fen
    self.history = history
  }

  func run(_ name: String, _ input: JSON) async -> (String, Bool) {
    var v = vocabulary
    var a = arrows
    let result = await tools.execute(name, input: input, fen: fen, history: history, vocabulary: &v, arrows: &a)
    vocabulary = v
    arrows = a
    return result
  }
}
