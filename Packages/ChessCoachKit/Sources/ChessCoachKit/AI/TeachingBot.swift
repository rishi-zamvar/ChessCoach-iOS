import ChessKit
import Foundation

/// The teaching opponent: Claude chooses each move from engine-vetted candidates to
/// create positions that train the learner's weaknesses. Code enforces the rules:
/// the move must be legal, in the candidate set, within a loss cap, and deliberate
/// "gifts" are rationed. Without AI (no key, offline, budget) it plays like Maia.
public struct TeachingBot: BotPlayer {
  public let host: EngineHost
  let client: LLMClient?
  let telemetry: Telemetry
  let random: RandomSource
  /// Plain-language summary of the learner's weaknesses and level (from the app).
  let brief: @Sendable () -> String
  let gifts: GiftCounter
  /// What this game trains (steers the bot's deliberate set-ups); nil = generic gifts.
  let focus: @Sendable () -> CoachFocus?

  public init(
    host: EngineHost, client: LLMClient?, telemetry: Telemetry, random: RandomSource = SystemRandom(),
    brief: @escaping @Sendable () -> String, focus: @escaping @Sendable () -> CoachFocus? = { nil }
  ) {
    self.focus = focus
    self.host = host
    self.client = client
    self.telemetry = telemetry
    self.random = random
    self.brief = brief
    gifts = GiftCounter()
  }

  public var name: String { "Coach" }
  public var rating: Int { 500 }
  public var kind: String { "teaching-bot" }

  public struct Candidate: Equatable, Sendable {
    public var uci: String
    public var san: String
    /// Expected points for the bot after this move (0…1).
    public var ep: Double
    public var maiaProbability: Double
    /// What the move leaves loose / allows (for "gift" moves).
    public var gives: String?
    /// Sets up the game's focus for the learner (a loose piece, a mate in one, a tactic).
    public var isGift = false
  }

  /// Loss caps: normal moves stay near Maia-level play; a gift may give up a piece.
  static let normalCap = 0.12
  static let giftCap = 0.45
  static let movesBetweenGifts = 8

  public func move(fen: String) async throws -> String {
    try await explainedMove(fen: fen).uci
  }

  public func explainedMove(fen: String) async throws -> (uci: String, why: String?) {
    try await telemetry.step("bot.move", metadata: ["kind": .string(kind)]) { ctx in
      let candidates = try await candidates(fen: fen)
      guard let best = candidates.max(by: { $0.ep < $1.ep }) else { throw EngineError.noBestMove }
      let focus = focus()
      let giftAllowed = await gifts.allowed(every: focus?.giftEvery ?? Self.movesBetweenGifts)
      let allowed = Self.choices(candidates, fen: fen, best: best.ep, focus: focus, giftDue: giftAllowed)
      var chosen: Candidate?
      var reason = "maia"
      var why: String?
      if let client, client.isAvailable, allowed.count > 1 {
        if let pick = try? await askClaude(fen: fen, allowed: allowed, client: client) {
          chosen = allowed.first { $0.uci == pick.uci }
          reason = pick.reason
          why = pick.explanation.flatMap { Self.isGrounded($0, fen: fen, uci: pick.uci) ? $0 : nil }
        }
      }
      if chosen == nil {
        // Maia-like fallback restricted to the allowed set.
        let policy = Dictionary(uniqueKeysWithValues: allowed.map { ($0.uci, max($0.maiaProbability, 0.01)) })
        chosen = allowed.first { $0.uci == MaiaBot.sample(policy, temperature: 1, random: random) } ?? allowed.first
      }
      guard let move = chosen else { throw EngineError.noBestMove }
      if move.isGift || (focus == nil && best.ep - move.ep > Self.normalCap) { await gifts.used() } else { await gifts.tick() }
      ctx.annotate("move", .string(move.uci))
      ctx.annotate("reason", .string(String(reason.prefix(200))))
      ctx.annotate("loss", .double(best.ep - move.ep))
      return (move.uci, move.uci == chosen?.uci ? why : nil)
    }
  }

  /// The learner-facing sentence may only mention this move and squares that hold a
  /// piece before or after it (no invented pieces, no other moves like the refutation).
  static func isGrounded(_ text: String, fen: String, uci: String) -> Bool {
    var session = GameSession(startFEN: fen)
    let before = session.position
    guard case .applied(let played) = session.apply(uci: uci), text.count <= 160 else { return false }
    let occupied = Set((before.pieces + session.position.pieces).map(\.square.notation))
    let bare = played.san.replacingOccurrences(of: #"[+#]"#, with: "", options: .regularExpression)
    return Explainer.mentions(in: text).allSatisfy { token in
      let t = token.replacingOccurrences(of: #"[+#]"#, with: "", options: .regularExpression)
      return t == bare || (t.count == 2 && occupied.contains(t))
    }
  }

  /// The moves the bot may play. Code rules, in order:
  /// 1. No mercy: a piece you left hanging gets taken.
  /// 2. A set-up for the focus when one is due (a mate-in-one gift may cost the game; that's the lesson).
  /// 3. Otherwise near-best human moves (with the old generic gifts only when there's no focus).
  static func choices(_ candidates: [Candidate], fen: String, best: Double, focus: CoachFocus?, giftDue: Bool) -> [Candidate] {
    if let me = Position(fen: fen)?.sideToMove {
      let loose = Set(FactExtractor.hangingPieces(fen: fen, of: me.opposite).map(\.square.notation))
      let takes = candidates.filter { loose.contains(String($0.uci.dropFirst(2).prefix(2))) && best - $0.ep <= normalCap }
      if !takes.isEmpty { return takes.sorted { $0.ep > $1.ep } }
    }
    if let focus, giftDue {
      let cap = focus == .mates ? 1.0 : giftCap
      let gifts = candidates.filter { $0.isGift && best - $0.ep <= cap + 1e-9 }
      if !gifts.isEmpty { return gifts }
    }
    return allowed(candidates.filter { !$0.isGift }, best: best, giftAllowed: focus == nil && giftDue)
  }

  static func allowed(_ candidates: [Candidate], best: Double, giftAllowed: Bool) -> [Candidate] {
    let cap = giftAllowed ? giftCap : normalCap
    let list = candidates.filter { best - $0.ep <= cap + 1e-9 }
    return list.isEmpty ? Array(candidates.sorted { $0.ep > $1.ep }.prefix(1)) : list
  }

  /// Stockfish MultiPV 5 + Maia priors + "what this move gives away".
  func candidates(fen: String) async throws -> [Candidate] {
    // Maia first, then all Stockfish work: one engine switch per move instead of two.
    let maia = (try? await host.search(.maia(rating: 1100), fen: fen, limit: .nodes(1)))?.policy ?? [:]
    let sf = try await host.search(.stockfish, fen: fen, limit: .depth(10), multipv: 5)
    // Include Maia's top human moves too (they may not be in Stockfish's top 5).
    var ucis = sf.lines.compactMap(\.pv.first)
    for (uci, _) in maia.sorted(by: { $0.value > $1.value }).prefix(4) where !ucis.contains(uci) { ucis.append(uci) }
    // Taking what you left loose, and set-ups for the game's focus.
    if let take = BoardScan.freeCapture(fen: fen)?.uci, !ucis.contains(take) { ucis.append(take) }
    let giftMoves = focus().map { BoardScan.gifts(fen: fen, focus: $0) } ?? []
    for uci in giftMoves where !ucis.contains(uci) { ucis.append(uci) }
    var result: [Candidate] = []
    for uci in ucis {
      var session = GameSession(startFEN: fen)
      guard case .applied(let played) = session.apply(uci: uci) else { continue }
      let ep: Double
      if let line = sf.lines.first(where: { $0.pv.first == uci }) {
        ep = WinChance.winPercent(line.score) / 100
      } else {
        let reply = try await host.search(.stockfish, fen: session.position.fen, limit: .depth(8))
        ep = 1 - (reply.lines.first.map { WinChance.winPercent($0.score) } ?? 50) / 100
      }
      let loose = FactExtractor.hangingPieces(fen: session.position.fen, of: played.color).first
      result.append(
        Candidate(uci: uci, san: played.san, ep: ep, maiaProbability: maia[uci] ?? 0,
          gives: loose.map { "leaves its \(FactExtractor.name(of: $0.kind)) on \($0.square.notation) loose" },
          isGift: giftMoves.contains(uci)))
    }
    return result
  }

  static let system = """
    You are a chess coach playing a training game against a beginner. Each turn you pick the move that best TEACHES them, \
    from a list of candidate moves that were already checked by an engine. Play like a natural human opponent most of the time. \
    When a candidate "gives" something (a loose piece) and it matches a weakness the learner is practicing, you may choose it \
    occasionally so the learner gets to spot and punish it. When every candidate is a set-up for the learner's focus, \
    pick the one that looks most natural.
    Call the play_move tool exactly once with one of the candidate moves, a short private reason, and an `explanation`: \
    one friendly sentence (under 20 words) the learner sees, saying what your move is trying to do as their opponent \
    (e.g. "I'm bringing my knight toward your king."). The explanation must never reveal a deliberate gift, hint at \
    their best reply, or name any move other than the one you played.
    """

  func askClaude(fen: String, allowed: [Candidate], client: LLMClient) async throws -> (uci: String, reason: String, explanation: String?) {
    let list = allowed.map { c in
      "- \(c.uci) (\(c.san)): engine expectation \(Int(c.ep * 100))%, human likelihood \(Int(c.maiaProbability * 100))%\(c.gives.map { ", \($0)" } ?? "")"
    }.joined(separator: "\n")
    let user = """
      Position (FEN): \(fen)
      Learner: \(brief())\(focus().map { "\nThis game's focus: \($0.title)." } ?? "")
      Candidates:
      \(list)
      Pick one with play_move.
      """
    let tool = AITool(
      name: "play_move", description: "Play one of the candidate moves.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "move": .object(["type": .string("string"), "enum": .array(allowed.map { .string($0.uci) })]),
          "reason": .object(["type": .string("string")]),
          "explanation": .object(["type": .string("string")]),
        ]),
        "required": .array([.string("move"), .string("reason"), .string("explanation")]),
        "additionalProperties": .bool(false),
      ]))
    // One call: read the play_move tool_use directly (no need to send a tool_result back).
    let turn = try await client.send(
      tier: .fast, system: Self.system,
      messages: [.object(["role": .string("user"), "content": .string(user)])], tools: [tool], maxTokens: 400, effort: "low",
      purpose: "teaching-bot")
    guard let call = turn.toolUses.first(where: { $0.name == "play_move" }), let uci = call.input["move"]?.stringValue,
      allowed.contains(where: { $0.uci == uci })
    else { throw AIError.badResponse }
    return (uci, call.input["reason"]?.stringValue ?? "", call.input["explanation"]?.stringValue)
  }
}

/// Rations deliberate teaching gifts (at most one every N bot moves).
actor GiftCounter {
  private var sinceLast = 99
  func allowed(every n: Int) -> Bool { sinceLast >= n }
  func used() { sinceLast = 0 }
  func tick() { sinceLast += 1 }
}
