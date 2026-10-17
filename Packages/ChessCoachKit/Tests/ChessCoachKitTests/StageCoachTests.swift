import ChessKit
import XCTest
@testable import ChessCoachKit

/// Scripted AI coach: a fixed verdict and fixed words.
final class FakeWriter: CoachWriter, @unchecked Sendable {
  var verdict: (kind: HoldUpKind, text: String)?
  var words: String?
  var moments: [CoachMoment.Kind] = []
  func write(_ moment: CoachMoment) async -> String? {
    moments.append(moment.kind)
    return words
  }
  func vet(_ moment: CoachMoment) async -> (kind: HoldUpKind, text: String)? {
    moments.append(moment.kind)
    return verdict
  }
}

@MainActor
final class StageCoachTests: XCTestCase {
  let italian = """
    [Side "white"]
    [Name "Test Italian"]
    [Summary "Aim at f7."]

    1. e4 { Grab the centre. } 1... e5 2. Nf3 { Hit e5. } 2... Nc6 ( 2... d6 { Philidor. [%dev] } 3. d4 { Open it. } ) 3. Bc4 { Aim at f7. } 3... Bc5
    """
  let straightLine = """
    [Side "white"]
    [Name "Test Italian"]
    [Summary "Aim at f7."]

    1. e4 { Grab the centre. } 1... e5 2. Nf3 { Hit e5. } 2... Nc6 3. Bc4 { Aim at f7. } 3... Bc5
    """

  func waitUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
  }

  func game(
    fen: String = GameSession.standardFEN, guide: OpeningGuide? = nil, coach: FakeCoach = FakeCoach(), writer: CoachWriter? = nil,
    bot: [String] = []
  ) -> GameController {
    GameController(
      config: PlayConfig(opponent: .teaching, userColor: .white, timeControl: .untimed),
      bot: ScriptedBot(bot), telemetry: Telemetry(sinks: []), store: nil, sounds: RecordingSoundSink(),
      startFEN: fen, minimumBotThink: .zero, coach: coach, focus: .freePieces, writer: writer, opening: guide, growth: "No coach games yet.")
  }

  func play(_ c: GameController, _ uci: String) {
    c.tap(Square(String(uci.prefix(2))))
    c.tap(Square(String(uci.dropFirst(2).prefix(2))))
  }

  func test_givenRepertoire_whenFollowingGame_thenKnowsLineNextMovesAndIdeas() throws {
    let guide = OpeningGuide(repertoires: [try Repertoire(pgn: italian, fileName: "t")])
    XCTAssertEqual(guide.nextMoves([]).map(\.san), ["e4"])
    XCTAssertEqual(Set(guide.nextMoves(["e2e4", "e7e5", "g1f3"]).map(\.san)), ["Nc6", "d6"])
    XCTAssertEqual(guide.lastNode(["e2e4", "e7e5", "g1f3", "d7d6"])?.isDeviation, true)
    XCTAssertEqual(guide.name(["e2e4"]), "Test Italian")
    XCTAssertTrue(guide.follow(["d2d4"]).isEmpty)
    XCTAssertFalse(OpeningGuide(style: "attacker", userColor: .black).repertoires.isEmpty)
    let withAdded = OpeningGuide(style: "attacker", added: ["positional-black-e4", "positional-white"], userColor: .black)
    XCTAssertTrue(withAdded.repertoires.map(\.fileName).contains("positional-black-e4"), "added openings join the guide")
    XCTAssertFalse(withAdded.repertoires.map(\.fileName).contains("positional-white"), "only your colour")
  }

  func test_givenStyles_whenRatingOpeningFit_thenSharpSuitsAttackersAndSolidSuitsPositional() {
    let all = RepertoireLibrary.all()
    let fried = all.first { $0.fileName == "attacker-white" }!
    let london = all.first { $0.fileName == "positional-white" }!
    XCTAssertEqual(OpeningFit.stars(fried, style: "attacker", quizScore: 1), 5)
    XCTAssertLessThanOrEqual(OpeningFit.stars(fried, style: "positional", quizScore: -1), 2)
    XCTAssertEqual(OpeningFit.stars(london, style: "positional", quizScore: -0.8), 5)
    XCTAssertGreaterThan(OpeningFit.stars(london, style: "positional", quizScore: 0), OpeningFit.stars(fried, style: "positional", quizScore: 0))
    XCTAssertEqual(OpeningFit.reason(fried, style: "positional", quizScore: -1), "Sharp and attacking: sharper than you usually like.")
    XCTAssertEqual(RepertoireLibrary.mine(style: "attacker", added: ["attacker-white", "positional-white"]).count, 4, "no duplicates")
  }

  func test_givenCoachGame_whenPlayingThroughRepertoire_thenIdeasHoldUpOffLineThenMiddlegame() async throws {
    let guide = OpeningGuide(repertoires: [try Repertoire(pgn: straightLine, fileName: "t")])
    let c = game(guide: guide)
    c.start()
    XCTAssertEqual(c.stage, .opening)
    XCTAssertEqual(c.coachLine?.headline, CoachVoice.openingStart)
    XCTAssertEqual(c.coachLine?.text, "Your Test Italian. Aim at f7.")

    play(c, "e2e4")
    XCTAssertEqual(c.coachLine?.text, "e4: Grab the centre.")
    XCTAssertNil(c.coachLine?.headline, "book ideas are shown, not spoken")
    await waitUntil { c.session.history.count == 2 }
    XCTAssertEqual(c.session.history.last?.san, "e5", "the bot plays the repertoire line")
    play(c, "g1f3")
    await waitUntil { c.session.history.count == 4 }

    // Leaving the line: hold up, with the repertoire move to show.
    play(c, "d2d4")
    XCTAssertEqual(c.phase, .coachPaused)
    XCTAssertEqual(c.coachPause?.kind, .leftBook)
    XCTAssertEqual(c.coachPause?.bestSAN, "Bc4")
    XCTAssertEqual(c.coachPause?.explanation, "Your Test Italian plays Bc4 here. Aim at f7.")
    XCTAssertEqual(c.coachLine?.headline, HoldUp.leftBook.line)
    c.takeBack()
    await c.hint()
    XCTAssertEqual(c.hintText, "Look at your bishops.", "in book, the hint is the repertoire move")

    play(c, "f1c4")
    await waitUntil { c.session.history.count == 6 }
    // The line is over: middlegame, with this game's focus.
    await waitUntil { c.stage == .middlegame && c.coachLine?.headline == CoachVoice.middlegameStart }
    XCTAssertEqual(c.coachLine?.text, CoachFocus.freePieces.intro)
  }

  func test_givenEndgameWithForcedMate_whenYourTurn_thenCoachAsksYouToFindIt() async {
    let fen = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    let coach = FakeCoach()
    coach.mates[FENTools.key(fen)] = 2
    let writer = FakeWriter()
    writer.words = "Their king is stuck on the back rank. Which check takes away its last square?"
    let c = game(fen: fen, coach: coach, writer: writer)
    c.start()
    await waitUntil { c.coachLine?.headline == CoachVoice.mateHere }
    XCTAssertEqual(c.coachLine?.headline, CoachVoice.mateHere)
    await waitUntil { c.coachLine?.text == writer.words }
    XCTAssertEqual(c.coachLine?.text, writer.words, "the AI coach's words replace the template")
  }

  func test_givenForcedMateThrownAway_whenCoachChecks_thenHoldsUp() async {
    let fen = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    let coach = FakeCoach()
    coach.mates[FENTools.key(fen)] = 3
    let c = game(fen: fen, coach: coach, bot: ["e8e7"])
    c.start()
    play(c, "a2a3")
    await waitUntil { c.phase == .coachPaused }
    XCTAssertEqual(c.coachPause?.kind, .missedMate)
    XCTAssertEqual(c.coachLine?.headline, HoldUp.missedForcedMate.line)
    XCTAssertTrue(c.coachPause?.explanation.hasPrefix("Mate in 3") == true)
  }

  func test_givenSmallSlip_whenAICoachFlagsIt_thenHoldUpUsesItsKindAndWords() async {
    let fen = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
    let coach = FakeCoach()
    coach.best[FENTools.key(fen)] = "e1d2"
    var s = GameSession(startFEN: fen)
    s.apply(uci: "a2a3")
    coach.wins[FENTools.key(s.position.fen)] = 53
    let writer = FakeWriter()
    writer.verdict = (.passiveKing, "Your king belongs in the centre now.")
    let c = game(fen: fen, coach: coach, writer: writer, bot: ["e8e7"])
    c.start()
    play(c, "a2a3")
    await waitUntil { c.phase == .coachPaused }
    XCTAssertEqual(c.coachPause?.kind, .passiveKing)
    XCTAssertEqual(c.coachPause?.explanation, "Your king belongs in the centre now.")
    XCTAssertEqual(c.coachLine?.headline, HoldUp.reviewed(.passiveKing)?.line)
    XCTAssertTrue(writer.moments.contains(.vet))
  }

  func test_givenAIText_whenChecked_thenRejectsTheHiddenAnswerAndInventedMoves() {
    let fen = "r3k3/8/8/3N4/8/8/8/4K3 w - - 0 1"
    let m = CoachMoment(
      kind: .opportunity, fen: fen, engine: CoachAssessment(bestUCI: "d5c7", winPercent: 90), stage: .middlegame, focus: .tactics,
      growth: "", recentSAN: ["Ra8"], template: "")
    let facts = LLMCoachWriter.facts(m)
    XCTAssertTrue(facts.text.contains("HIDDEN"))
    XCTAssertNil(LLMCoachWriter.checked("Play Nc7+ and fork them.", facts: facts))
    XCTAssertNil(LLMCoachWriter.checked("Look at c7.", facts: facts))
    XCTAssertNil(LLMCoachWriter.checked("Qh5 wins.", facts: facts))
    XCTAssertEqual(
      LLMCoachWriter.checked("Their rook and king sit on the same rank. Which of your pieces can reach both?", facts: facts),
      "Their rook and king sit on the same rank. Which of your pieces can reach both?")
    XCTAssertNotNil(LLMCoachWriter.checked("Your knight on d5 is your best piece.", facts: facts))
  }
}
