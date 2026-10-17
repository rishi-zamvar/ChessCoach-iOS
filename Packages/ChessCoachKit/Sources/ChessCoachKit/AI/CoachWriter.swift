import ChessKit
import Foundation

/// One coaching moment, with the data the AI coach writes from.
public struct CoachMoment: Sendable {
  public enum Kind: String, Sendable {
    /// Before the learner moves (never give the move away).
    case middlegameStart, endgameStart, mateAvailable, opportunity
    /// After the learner's move, the game paused.
    case holdUp
    /// After the learner's move: should we pause at all?
    case vet
  }

  public var kind: Kind
  /// The position the learner faced (before their move for holdUp/vet).
  public var fen: String
  public var played: String?
  public var engine: CoachAssessment?
  /// Engine's best reply after the played move.
  public var punish: [String] = []
  public var label: MoveClass?
  public var holdUp: HoldUpKind?
  public var stage: GamePhaseKind
  public var opening: String?
  public var focus: CoachFocus?
  /// Long-run picture of the learner (WeaknessTally.summary).
  public var growth: String
  public var recentSAN: [String]
  /// What the coach says if the AI is slow, offline or ungrounded.
  public var template: String

  public init(
    kind: Kind, fen: String, played: String? = nil, engine: CoachAssessment? = nil, punish: [String] = [], label: MoveClass? = nil,
    holdUp: HoldUpKind? = nil, stage: GamePhaseKind, opening: String? = nil, focus: CoachFocus?, growth: String,
    recentSAN: [String], template: String
  ) {
    self.kind = kind
    self.fen = fen
    self.played = played
    self.engine = engine
    self.punish = punish
    self.label = label
    self.holdUp = holdUp
    self.stage = stage
    self.opening = opening
    self.focus = focus
    self.growth = growth
    self.recentSAN = recentSAN
    self.template = template
  }
}

/// The coach's words. Code decides *when* the coach speaks and the fixed spoken headline;
/// the writer supplies the sentence on screen.
public protocol CoachWriter: Sendable {
  /// Coach text for the moment, or nil to keep the template.
  func write(_ moment: CoachMoment) async -> String?
  /// Vets the learner's move against their growth goals: a pause kind and why, or nil.
  func vet(_ moment: CoachMoment) async -> (kind: HoldUpKind, text: String)?
}

/// Claude Haiku, fed engine + board facts; every move or square it names is checked.
public struct HaikuCoachWriter: CoachWriter {
  let client: AnthropicClient
  let timeout: Duration

  public init(client: AnthropicClient, timeout: Duration = .milliseconds(2500)) {
    self.client = client
    self.timeout = timeout
  }

  static let system = """
    You are a real chess coach sitting next to an adult improver (about 400–700 rated) during a training game in a phone app.
    You talk like a good human coach: calm, specific, one idea at a time, in plain English, second person.
    - Never state the obvious (e.g. "your queen is attacked" when it plainly is). Point at what they would miss: the idea, \
    the habit, the plan, the opponent's intention.
    - Prefer a question that makes them think ("What does their last move want?") to handing over the answer, before they move.
    - Tie advice to their long-run goals when it fits (the growth record and this game's focus).
    - Use ONLY the FACTS. Every move (SAN) or square you mention must appear in the FACTS. Never invent pieces, moves or lines.
    - When the FACTS mark the best move as hidden, do not name it, its piece's destination, or the line.
    - At most 2 short sentences (under 200 characters). No markdown, no emoji, no numbers from the engine.
    """

  public func write(_ moment: CoachMoment) async -> String? {
    guard client.isAvailable else { return nil }
    let facts = Self.facts(moment)
    let ask = "FACTS:\n\(facts.text)\n\nWrite what the coach says now (\(Self.purpose(moment)))."
    return await race { [client] in
      guard
        let turn = try? await client.send(
          model: AnthropicClient.explainModel, system: Self.system,
          messages: [.object(["role": .string("user"), "content": .string(ask)])], maxTokens: 160, effort: "low",
          purpose: "coach-\(moment.kind.rawValue)")
      else { return nil }
      return Self.checked(turn.text, facts: facts)
    }
  }

  public func vet(_ moment: CoachMoment) async -> (kind: HoldUpKind, text: String)? {
    guard client.isAvailable else { return nil }
    let facts = Self.facts(moment)
    let kinds = ["none"] + HoldUpKind.vettable.filter { $0 != .passiveKing || moment.stage == .endgame }.map(\.rawValue)
    let tool = AITool(
      name: "verdict", description: "Pause the game to teach, or let it go on.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "kind": .object(["type": .string("string"), "enum": .array(kinds.map { .string($0) })]),
          "text": .object(["type": .string("string"), "description": .string("What the coach says if pausing (empty for none).")]),
        ]),
        "required": .array([.string("kind"), .string("text")]), "additionalProperties": .bool(false),
      ]))
    let ask = """
      FACTS:
      \(facts.text)

      The learner just played this move. Pause the game only if it is a real learning moment for THEIR goals \
      (growth record, focus, stage): missedTactic (a clear tactic skipped), allowsTactic (lets the opponent start one), \
      ignoredThreat (didn't deal with what the opponent's last move threatened), aimless (no purpose when a clear plan existed), \
      passiveKing (endgame, king left idle). Small inaccuracies that don't touch their goals: none. Call verdict once.
      """
    return await race { [client] in
      guard
        let turn = try? await client.send(
          model: AnthropicClient.explainModel, system: Self.system,
          messages: [.object(["role": .string("user"), "content": .string(ask)])], tools: [tool], maxTokens: 200, effort: "low",
          purpose: "coach-vet"),
        let input = turn.toolUses.first?.input, let raw = input["kind"]?.stringValue,
        let kind = HoldUpKind(rawValue: raw), HoldUpKind.vettable.contains(kind),
        let text = Self.checked(input["text"]?.stringValue ?? "", facts: facts)
      else { return nil }
      return (kind, text)
    }
  }

  private func race<T: Sendable>(_ work: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
      group.addTask { await work() }
      group.addTask { [timeout] in try? await Task.sleep(for: timeout); return nil }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  static func purpose(_ m: CoachMoment) -> String {
    switch m.kind {
    case .middlegameStart: "the opening is over: give the plan for the middlegame in this position"
    case .endgameStart: "the endgame has started: what matters now in this position"
    case .mateAvailable: "there is a forced mate for the learner: nudge them to find it without giving it away"
    case .opportunity: "the opponent just slipped: get the learner to look for how to punish it, without giving it away"
    case .holdUp: "the game is paused on the learner's move: explain what went wrong and the habit that prevents it"
    case .vet: "decide whether to pause"
    }
  }

  // MARK: - Facts

  struct Facts {
    var text: String
    /// Moves/squares the text may mention.
    var vocabulary: Set<String>
    /// Moves/squares it must not mention (the hidden answer).
    var forbidden: Set<String>
  }

  static func facts(_ m: CoachMoment) -> Facts {
    var lines: [String] = []
    var vocab = Set<String>()
    var forbidden = Set<String>()
    guard let position = Position(fen: m.fen) else { return Facts(text: "", vocabulary: [], forbidden: []) }
    let learner = position.sideToMove
    // Any legal move here may be named (except a hidden best move, below).
    vocab.formUnion(BoardScan.legalUCIs(fen: m.fen).compactMap { FactExtractor.sanLine(fen: m.fen, ucis: [$0]).first })
    lines.append("Learner plays \(learner == .white ? "White" : "Black"). Stage: \(m.stage.rawValue).")
    if let opening = m.opening { lines.append("Opening: \(opening).") }
    if let focus = m.focus { lines.append("This game's focus: \(focus.title).") }
    lines.append("Growth record: \(m.growth)")
    if !m.recentSAN.isEmpty { lines.append("Recent moves: \(m.recentSAN.suffix(8).joined(separator: " "))") }
    for color in [learner, learner.opposite] {
      let pieces = position.pieces.filter { $0.color == color }.sorted { PieceValue.of($0.kind) > PieceValue.of($1.kind) }
      let who = color == learner ? "Learner's" : "Opponent's"
      lines.append("\(who) pieces: " + pieces.map { "\(FactExtractor.name(of: $0.kind)) \($0.square.notation)" }.joined(separator: ", "))
      vocab.formUnion(pieces.map(\.square.notation))
      let loose = FactExtractor.hangingPieces(fen: m.fen, of: color)
      if !loose.isEmpty {
        lines.append("\(who) pieces that can be won: " + loose.map { "\(FactExtractor.name(of: $0.kind)) \($0.square.notation)" }.joined(separator: ", "))
      }
    }
    if let e = m.engine {
      let mood =
        e.mate.map { $0 > 0 ? "learner has a forced mate in \($0)" : "learner is getting mated" }
        ?? (e.winPercent > 70 ? "learner is clearly better" : e.winPercent < 30 ? "learner is clearly worse" : "roughly balanced")
      lines.append("Assessment: \(mood).")
      let bestLine = FactExtractor.sanLine(fen: m.fen, ucis: Array(e.line.prefix(5)))
      let bestFacts = FactExtractor.moveFacts(fen: m.fen, uci: e.bestUCI)
      let themes = bestFacts.map { $0.motifs.map(\.displayName).joined(separator: ", ") } ?? ""
      if m.played == nil {
        // Before the learner moves the answer never reaches the prompt: only what kind of idea it is.
        lines.append("Best move: HIDDEN\(themes.isEmpty ? " (a quiet move)" : " (themes: \(themes))").")
        if let first = bestLine.first { forbidden.insert(first) }
        forbidden.insert(String(e.bestUCI.dropFirst(2).prefix(2)))
      }
    }
    if let played = m.played, let e = m.engine,
      let sheet = FactExtractor.sheet(fen: m.fen, played: played, bestLine: e.line, punishLine: m.punish, ply: m.recentSAN.count)
    {
      lines.append(AIExplainer.factsBlock(sheet: sheet, label: m.label ?? .good, isUser: true, template: m.template))
      vocab.formUnion(sheet.vocabulary)
      var after = GameSession(startFEN: m.fen)
      after.apply(uci: played)
      vocab.formUnion(after.position.pieces.map(\.square.notation))
      if let hold = m.holdUp { lines.append("The coach paused for: \(hold.rawValue).") }
    } else if m.played == nil {
      lines.append("Coach's default line: \(m.template)")
    }
    // The opponent's last move and what it does.
    if m.played == nil, let last = m.recentSAN.last { lines.append("Opponent just played: \(last).") }
    return Facts(text: lines.joined(separator: "\n"), vocabulary: vocab.subtracting(forbidden), forbidden: forbidden)
  }

  /// The text if it's short, non-empty and only names allowed moves/squares.
  static func checked(_ raw: String, facts: Facts) -> String? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 240 else { return nil }
    let bare = { (t: String) in t.replacingOccurrences(of: #"[+#]"#, with: "", options: .regularExpression) }
    let vocab = Set(facts.vocabulary.map(bare))
    let banned = Set(facts.forbidden.map(bare))
    let ok = Explainer.mentions(in: text).allSatisfy { token in
      let t = bare(token)
      return !banned.contains(t) && vocab.contains(t)
    }
    return ok ? text : nil
  }
}
