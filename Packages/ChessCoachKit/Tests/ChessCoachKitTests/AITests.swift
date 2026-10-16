import XCTest
@testable import ChessCoachKit

/// Scripted Messages API: returns queued JSON bodies, records requests.
final class FakeTransport: AITransport, @unchecked Sendable {
  var responses: [(Int, String)] = []
  var requests: [(headers: [String: String], body: JSON)] = []
  func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
    requests.append((headers, try JSONDecoder().decode(JSON.self, from: body)))
    let (status, text) = responses.isEmpty ? (200, Self.text("ok")) : responses.removeFirst()
    return (status, Data(text.utf8))
  }

  static func text(_ t: String, model: String = "claude-haiku-4-5", stop: String = "end_turn") -> String {
    """
    {"id":"msg_1","model":"\(model)","stop_reason":"\(stop)","content":[{"type":"text","text":\(JSON.string(t).text)}],
     "usage":{"input_tokens":1000,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
    """
  }

  static func toolUse(_ name: String, input: String) -> String {
    """
    {"id":"msg_2","model":"claude-sonnet-5-5","stop_reason":"tool_use","content":[
      {"type":"thinking","thinking":"","signature":"x"},
      {"type":"tool_use","id":"toolu_1","name":"\(name)","input":\(input)}],
     "usage":{"input_tokens":500,"output_tokens":40}}
    """
  }
}

final class AIClientTests: XCTestCase {
  func makeClient(_ t: FakeTransport, key: String? = "sk-test", store: AIStore? = nil, cap: Double = 80) -> AnthropicClient {
    AnthropicClient(keyProvider: { key }, transport: t, telemetry: Telemetry(sinks: []), ledger: store, monthlyCapUSD: cap)
  }

  func test_givenRequest_whenSent_thenHeadersCachedSystemAndUsageCost() async throws {
    let t = FakeTransport()
    t.responses = [(200, FakeTransport.text("hi"))]
    let store = AIStore(database: try AppDatabase.inMemory())
    let turn = try await makeClient(t, store: store).send(
      model: "claude-haiku-4-5", system: "sys", messages: [.object(["role": .string("user"), "content": .string("x")])], purpose: "test")
    XCTAssertEqual(turn.text, "hi")
    let req = t.requests[0]
    XCTAssertEqual(req.headers["x-api-key"], "sk-test")
    XCTAssertEqual(req.headers["anthropic-version"], "2023-06-01")
    XCTAssertNil(req.headers["anthropic-beta"])
    XCTAssertEqual(req.body["system"]?.arrayValue?.first?["cache_control"]?["type"]?.stringValue, "ephemeral")
    XCTAssertEqual(turn.usage.costUSD, (1000 * 1 + 100 * 5) / 1_000_000, accuracy: 1e-12)
    XCTAssertEqual(store.spentThisMonth(), turn.usage.costUSD, accuracy: 1e-12)
  }

  func test_givenSonnet55_whenSent_thenServerSideFallbackDefault() async throws {
    let t = FakeTransport()
    _ = try await makeClient(t).send(model: "claude-sonnet-5-5", system: "s", messages: [], purpose: "t")
    XCTAssertEqual(t.requests[0].headers["anthropic-beta"], "server-side-fallback-2026-07-01")
    XCTAssertEqual(t.requests[0].body["fallbacks"]?.stringValue, "default")
  }

  func test_givenNoKey_whenSent_thenNoKeyError() async {
    do {
      _ = try await makeClient(FakeTransport(), key: nil).send(model: "m", system: "s", messages: [], purpose: "t")
      XCTFail()
    } catch { XCTAssertEqual(error as? AIError, .noKey) }
  }

  func test_givenSpendOverCap_whenSent_thenBudgetExceededWithoutCalling() async throws {
    let store = AIStore(database: try AppDatabase.inMemory())
    store.record(AIUsage(model: "claude-sonnet-5-5", inputTokens: 0, outputTokens: 10_000_000, cacheReadTokens: 0, cacheWriteTokens: 0), purpose: "x", latencyMs: 1)
    let t = FakeTransport()
    let client = makeClient(t, store: store, cap: 80)
    XCTAssertFalse(client.isAvailable)
    do {
      _ = try await client.send(model: "m", system: "s", messages: [], purpose: "t")
      XCTFail()
    } catch AIError.budgetExceeded(let spent) { XCTAssertEqual(spent, 100, accuracy: 0.01) }
    XCTAssertTrue(t.requests.isEmpty)
  }

  func test_givenRefusalOrHTTPError_whenSent_thenThrows() async {
    let t = FakeTransport()
    t.responses = [(200, FakeTransport.text("", stop: "refusal")), (429, #"{"error":{"message":"slow down"}}"#)]
    let client = makeClient(t)
    do { _ = try await client.send(model: "m", system: "s", messages: [], purpose: "t"); XCTFail() } catch { XCTAssertEqual(error as? AIError, .refused) }
    do { _ = try await client.send(model: "m", system: "s", messages: [], purpose: "t"); XCTFail() } catch {
      XCTAssertEqual(error as? AIError, .http(status: 429, message: "slow down"))
    }
  }

  func test_givenToolUse_whenLoopRuns_thenResultsSentBackAndAssistantContentEchoed() async throws {
    let t = FakeTransport()
    t.responses = [(200, FakeTransport.toolUse("legal_moves", input: "{}")), (200, FakeTransport.text("done", model: "claude-sonnet-5-5"))]
    let tool = AITool(name: "legal_moves", description: "d", inputSchema: .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)]))
    let (text, calls) = try await makeClient(t).runTools(model: "claude-sonnet-5-5", system: "s", user: "u", tools: [tool], purpose: "t") { name, _ in
      ("[\"e4\"]", false)
    }
    XCTAssertEqual(text, "done")
    XCTAssertEqual(calls.map(\.name), ["legal_moves"])
    let second = t.requests[1].body["messages"]!.arrayValue!
    XCTAssertEqual(second.count, 3)
    XCTAssertEqual(second[1]["content"]?.arrayValue?.first?["type"]?.stringValue, "thinking", "assistant content echoed unchanged")
    let result = second[2]["content"]!.arrayValue![0]
    XCTAssertEqual(result["type"]?.stringValue, "tool_result")
    XCTAssertEqual(result["tool_use_id"]?.stringValue, "toolu_1")
    XCTAssertEqual(t.requests[0].body["tools"]?.arrayValue?.first?["strict"], .bool(true))
  }
}

final class AIExplainerTests: XCTestCase {
  let fen = "4k3/8/4p3/8/8/8/8/3QK3 w - - 0 1"

  func sheet() -> FactSheet {
    FactExtractor.sheet(fen: fen, played: "d1d5", bestLine: ["d1d7"], punishLine: ["e6d5"], ply: 30)!
  }

  func test_givenGroundedReply_whenExplained_thenAIAndCached() async throws {
    let t = FakeTransport()
    t.responses = [(200, FakeTransport.text("Qd5 walks into exd5 — your queen on d5 is lost."))]
    let store = AIStore(database: try AppDatabase.inMemory())
    let explainer = AIExplainer(client: AnthropicClient(keyProvider: { "k" }, transport: t, telemetry: Telemetry(sinks: []), ledger: store), store: store)
    let r1 = await explainer.explain(sheet: sheet(), label: .blunder, isUser: true, template: "template")
    XCTAssertEqual(r1.origin, .ai)
    let r2 = await explainer.explain(sheet: sheet(), label: .blunder, isUser: true, template: "template")
    XCTAssertEqual(r2.origin, .cache)
    XCTAssertEqual(t.requests.count, 1)
    let prompt = t.requests[0].body["messages"]!.arrayValue![0]["content"]!.stringValue!
    XCTAssertTrue(prompt.contains("Opponent's best reply: exd5"), prompt)
  }

  func test_givenInventedMoveTwice_whenExplained_thenRetriesThenTemplate() async {
    let t = FakeTransport()
    t.responses = [(200, FakeTransport.text("Better was Nf3 hitting h7.")), (200, FakeTransport.text("Try Bb5 instead."))]
    let explainer = AIExplainer(client: AnthropicClient(keyProvider: { "k" }, transport: t, telemetry: Telemetry(sinks: []), ledger: nil), store: nil)
    let r = await explainer.explain(sheet: sheet(), label: .blunder, isUser: true, template: "TEMPLATE")
    XCTAssertEqual(r.origin, .template)
    XCTAssertEqual(r.text, "TEMPLATE")
    XCTAssertEqual(t.requests.count, 2)
    let retry = t.requests[1].body["messages"]!.arrayValue![0]["content"]!.stringValue!
    XCTAssertTrue(retry.contains("not in the FACTS"))
  }

  func test_givenNoKey_whenExplained_thenTemplateWithoutCalls() async {
    let t = FakeTransport()
    let explainer = AIExplainer(client: AnthropicClient(keyProvider: { nil }, transport: t, telemetry: Telemetry(sinks: []), ledger: nil), store: nil)
    let r = await explainer.explain(sheet: sheet(), label: .blunder, isUser: true, template: "T")
    XCTAssertEqual(r.origin, .template)
    XCTAssertTrue(t.requests.isEmpty)
  }
}

final class TeachingBotRuleTests: XCTestCase {
  func c(_ uci: String, _ ep: Double) -> TeachingBot.Candidate { .init(uci: uci, san: uci, ep: ep, maiaProbability: 0.2, gives: nil) }

  func test_givenCandidates_whenNoGiftAllowed_thenOnlyWithinNormalCap() {
    let allowed = TeachingBot.allowed([c("a", 0.6), c("b", 0.5), c("c", 0.3)], best: 0.6, giftAllowed: false)
    XCTAssertEqual(allowed.map(\.uci), ["a", "b"])
  }

  func test_givenGiftAllowed_whenFiltered_thenBiggerLossesAllowedButNotThrowingTheGame() {
    let allowed = TeachingBot.allowed([c("a", 0.6), c("c", 0.3), c("d", 0.05)], best: 0.6, giftAllowed: true)
    XCTAssertEqual(allowed.map(\.uci), ["a", "c"])
  }

  func test_givenEverythingTooBad_whenFiltered_thenBestOnly() {
    XCTAssertEqual(TeachingBot.allowed([c("x", 0.2), c("y", 0.9)], best: 0.95, giftAllowed: false).map(\.uci), ["y"])
  }

  func test_givenGiftCounter_whenUsed_thenRationed() async {
    let g = GiftCounter()
    let first = await g.allowed(every: 8)
    XCTAssertTrue(first)
    await g.used()
    for _ in 0..<7 { await g.tick() }
    let early = await g.allowed(every: 8)
    XCTAssertFalse(early)
    await g.tick()
    let later = await g.allowed(every: 8)
    XCTAssertTrue(later)
  }
}
