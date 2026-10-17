import ChessKit
import XCTest
@testable import ChessCoachKit

final class CoachToolsTests: XCTestCase {
  let tools = CoachTools(host: nil, profile: { "rating 500" })

  func run(_ name: String, _ input: JSON = .object([:]), fen: String = GameSession.standardFEN) async -> (String, Bool, Set<String>, [Arrow]) {
    var v = Set<String>()
    var a: [Arrow] = []
    let (text, err) = await tools.execute(name, input: input, fen: fen, history: ["e4"], vocabulary: &v, arrows: &a)
    return (text, err, v, a)
  }

  func test_givenStart_whenLegalMoves_thenTwentyMovesInSANAndVocabulary() async {
    let (text, err, vocab, _) = await run("legal_moves")
    XCTAssertFalse(err)
    let moves = (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    XCTAssertEqual(moves.count, 20)
    XCTAssertTrue(vocab.contains("Nf3"))
  }

  func test_givenHangingKnight_whenFacts_thenListsLoosePieceAndCaptures() async {
    let (text, _, vocab, _) = await run("position_facts", fen: "4k3/8/4p3/3N4/8/8/8/4K3 b - - 0 1")
    XCTAssertTrue(text.contains("knight on d5"), text)
    XCTAssertTrue(vocab.contains("exd5"))
  }

  func test_givenDrawInput_whenExecuted_thenArrowsCollectedAndInvalidSkipped() async {
    let input: JSON = .object(["arrows": .array([
      .object(["from": .string("e2"), "to": .string("e4"), "color": .string("green")]),
      .object(["from": .string("z9"), "to": .string("e4"), "color": .string("red")]),
    ])])
    let (_, _, _, arrows) = await run("draw", input)
    XCTAssertEqual(arrows, [Arrow(from: Square("e2"), to: Square("e4"), color: .green)])
  }

  func test_givenNoEngine_whenEvaluate_thenToolError() async {
    let (_, err, _, _) = await run("evaluate_moves")
    XCTAssertTrue(err)
  }

  func test_givenDefinitions_whenStrict_thenEverySchemaClosed() {
    func closed(_ s: JSON) -> Bool {
      guard s["type"]?.stringValue == "object" else { return true }
      guard s["additionalProperties"] == .bool(false), s["required"] != nil else { return false }
      var props: [String: JSON] = [:]
      if case .object(let o)? = s["properties"] { props = o }
      for p in props.values {
        if !closed(p) { return false }
        if let items = p["items"], !closed(items) { return false }
      }
      return true
    }
    for tool in CoachTools.definitions { XCTAssertTrue(closed(tool.inputSchema), tool.name) }
  }
}

final class AskCoachTests: XCTestCase {
  func test_givenToolThenGroundedAnswer_whenAsked_thenGroundedWithArrows() async throws {
    let t = FakeTransport()
    t.responses = [
      (200, FakeTransport.toolUse("legal_moves", input: "{}")),
      (200, FakeTransport.toolUse("draw", input: #"{"arrows":[{"from":"e2","to":"e4","color":"green"}]}"#)),
      (200, FakeTransport.text("Start with e4 or Nf3 to grab the centre.", model: "claude-sonnet-5-5")),
    ]
    let coach = AskCoach(client: LLMClient(config: { LLMConfig(provider: .anthropic, apiKey: "k") }, transport: t, telemetry: Telemetry(sinks: []), ledger: nil),
      tools: CoachTools(host: nil, profile: { "" }))
    let answer = try await coach.ask("What should I play?", fen: GameSession.standardFEN, history: [])
    XCTAssertTrue(answer.grounded, answer.text)
    XCTAssertEqual(answer.arrows.count, 1)
  }

  func test_givenAnswerWithInventedMove_whenAsked_thenNotGrounded() async throws {
    let t = FakeTransport()
    t.responses = [(200, FakeTransport.text("Play Qh5 and attack f7.", model: "claude-sonnet-5-5"))]
    let coach = AskCoach(client: LLMClient(config: { LLMConfig(provider: .anthropic, apiKey: "k") }, transport: t, telemetry: Telemetry(sinks: []), ledger: nil),
      tools: CoachTools(host: nil, profile: { "" }))
    let answer = try await coach.ask("What now?", fen: GameSession.standardFEN, history: [])
    XCTAssertFalse(answer.grounded)
  }
}
