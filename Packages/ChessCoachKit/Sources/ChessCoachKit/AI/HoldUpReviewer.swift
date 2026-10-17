import Foundation

/// Decides whether a borderline move deserves a "Hold up" the rules didn't catch.
/// Answers only a fixed kind; the words come from `HoldUp.reviewed`.
public protocol HoldUpReviewer: Sendable {
  func review(fen: String, played: String, best: String, label: MoveClass, focus: CoachFocus?) async -> HoldUpKind?
}

/// Haiku in the background. Bounded by a timeout so the game never waits long.
public struct HaikuHoldUpReviewer: HoldUpReviewer {
  let client: AnthropicClient
  let timeout: Duration

  public init(client: AnthropicClient, timeout: Duration = .milliseconds(2500)) {
    self.client = client
    self.timeout = timeout
  }

  static let system = """
    You are a chess coach watching a beginner's training game. Decide if their last move deserves pausing the game \
    to teach something. Pause only for a real learning moment: they skipped a clear tactic (missedTactic) or their move \
    lets the opponent start one (allowsTactic). Otherwise answer none. Call the verdict tool once.
    """

  public func review(fen: String, played: String, best: String, label: MoveClass, focus: CoachFocus?) async -> HoldUpKind? {
    guard client.isAvailable else { return nil }
    let ask: @Sendable () async -> HoldUpKind? = { [client] in
      let tool = AITool(
        name: "verdict", description: "Pause or not.",
        inputSchema: .object([
          "type": .string("object"),
          "properties": .object(["kind": .object(["type": .string("string"), "enum": .array(["none", "missedTactic", "allowsTactic"].map { .string($0) })])]),
          "required": .array([.string("kind")]), "additionalProperties": .bool(false),
        ]))
      let user = """
        Position before the move (FEN): \(fen)
        They played \(played); engine best was \(best); engine verdict: \(label.displayName.lowercased()).
        \(focus.map { "This game's focus: \($0.title)." } ?? "")
        """
      guard
        let turn = try? await client.send(
          model: AnthropicClient.explainModel, system: Self.system,
          messages: [.object(["role": .string("user"), "content": .string(user)])], tools: [tool], maxTokens: 100, effort: "low",
          purpose: "hold-up"),
        let kind = turn.toolUses.first?.input["kind"]?.stringValue
      else { return nil }
      return HoldUpKind(rawValue: kind)
    }
    return await withTaskGroup(of: HoldUpKind?.self) { group in
      group.addTask { await ask() }
      group.addTask { [timeout] in try? await Task.sleep(for: timeout); return nil }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }
}
