import XCTest
@testable import ChessCoachKit

final class GameAnalyzerTests: XCTestCase {
  static let scholarsPGN = """
    [Event "Test"]
    [White "Opp"]
    [Black "Zammy009"]
    [Result "1-0"]
    [TimeControl "600"]

    1. e4 {[%clk 0:09:58]} 1... e5 {[%clk 0:09:57]} 2. Bc4 {[%clk 0:09:55]} 2... Nc6 {[%clk 0:09:50]} \
    3. Qh5 {[%clk 0:09:50]} 3... Nf6 {[%clk 0:00:30]} 4. Qxf7# {[%clk 0:09:45]} 1-0
    """

  func analyze(cache: PositionCache? = nil, sink: MemorySink = MemorySink()) async throws -> GameAnalysis {
    let host = EngineHost(assets: EngineHostTests.assets)
    let analyzer = GameAnalyzer(host: host, telemetry: Telemetry(sinks: [sink]), depth: 10, cache: cache)
    let result = try await analyzer.analyze(gameID: "g", pgn: Self.scholarsPGN, userColor: "black", timeControl: "600")
    await host.shutdown()
    return result
  }

  func test_givenScholarsMateGame_whenAnalyzed_thenNf6IsBlunderThatAllowedMate() async throws {
    let analysis = try await analyze()
    XCTAssertEqual(analysis.moves.count, 7)
    let nf6 = analysis.moves[5]
    XCTAssertEqual(nf6.san, "Nf6")
    XCTAssertEqual(nf6.label, .blunder)
    XCTAssertEqual(nf6.mistakeType, .allowedTactic)
    XCTAssertTrue(nf6.explanation.contains("Qxf7#"), nf6.explanation)
    XCTAssertTrue(nf6.timeTrouble, "30s left of 600 is under 10%")
    XCTAssertEqual(analysis.moves[6].label, .best)
    XCTAssertTrue(analysis.keyMoments.contains(6))
  }

  func test_givenAnalysis_whenGraphBuilt_thenEndsAtWhiteWin100AndAccuraciesSet() async throws {
    let analysis = try await analyze()
    XCTAssertEqual(analysis.whiteWin.count, 8)
    XCTAssertEqual(analysis.whiteWin.last, 100)
    XCTAssertNotNil(analysis.accuracyWhite)
    XCTAssertLessThan(analysis.accuracyBlack!, analysis.accuracyWhite!)
    XCTAssertEqual(analysis.counts(for: "black")[.blunder], 1)
  }

  func test_givenAnalysis_whenRun_thenProgressLoggedPerPosition() async throws {
    let sink = MemorySink()
    _ = try await analyze(sink: sink)
    let progress = sink.events(named: "analysis.game").filter { $0.phase == .progress }
    XCTAssertEqual(progress.last?.done, 8)
    XCTAssertEqual(progress.last?.total, 8)
    XCTAssertEqual(sink.events(named: "analysis.game").last?.phase, .finish)
  }

  func test_givenCache_whenAnalyzedTwice_thenSecondRunSkipsEngine() async throws {
    let database = try AppDatabase.inMemory()
    let cache = PositionCache(database: database)
    _ = try await analyze(cache: cache)
    let sink = MemorySink()
    _ = try await analyze(cache: cache, sink: sink)
    XCTAssertTrue(sink.events(named: "engine.search").isEmpty, "all positions should come from cache")
  }

  func test_givenSavedAnalysis_whenLoadedAndAggregated_thenRoundTripsAndCountsMistakes() async throws {
    let analysis = try await analyze()
    let store = AnalysisStore(database: try AppDatabase.inMemory())
    try store.save(analysis, endedAt: Date())
    XCTAssertEqual(try store.analysis(gameID: "g"), analysis)
    XCTAssertEqual(try store.analyzedGameIDs(), ["g"])
    let patterns = try store.recurringPatterns()
    XCTAssertTrue(patterns.contains { $0.key == "type:allowedTactic" && $0.count == 1 })
    XCTAssertTrue(patterns.contains { $0.key == "time" })
  }

  func test_givenUnreadablePGN_whenAnalyzed_thenThrows() async {
    let analyzer = GameAnalyzer(host: EngineHost(assets: EngineHostTests.assets), telemetry: Telemetry(sinks: []))
    do {
      _ = try await analyzer.analyze(gameID: "x", pgn: "1. e4 e5 2. Ke3 Kd6 3. Qz9 *x", userColor: "white", timeControl: "-")
      XCTFail("expected throw")
    } catch {
      XCTAssertEqual(error as? AnalysisError, .unreadablePGN)
    }
  }

  func test_givenClockComments_whenParsed_thenSecondsInOrder() {
    XCTAssertEqual(PGNClocks.parse(Self.scholarsPGN).prefix(3), [598, 597, 595])
    XCTAssertEqual(PGNClocks.parse("1. e4 {[%clk 0:02:59.9]}"), [179.9])
    XCTAssertEqual(PGNClocks.baseSeconds(timeControl: "180+2"), 180)
    XCTAssertNil(PGNClocks.baseSeconds(timeControl: "1/86400"))
  }

  func test_givenImportedGame_whenMappedToRecord_thenChessComSourceWithElos() {
    let imported = ImportedGame(
      id: "https://www.chess.com/game/live/1", pgn: Self.scholarsPGN, white: "Opp", black: "Zammy009",
      whiteElo: 320, blackElo: 305, userColor: "black", result: "1-0", termination: "checkmate",
      timeControl: "600", timeClass: "rapid", endedAt: Date(timeIntervalSince1970: 5), chessComAccuracy: nil)
    let record = GameRecord(imported: imported)
    XCTAssertEqual(record.source, .chesscom)
    XCTAssertEqual(record.blackElo, 305)
    XCTAssertEqual(record.opponentKind, "chesscom")
  }
}

final class OpeningBookTests: XCTestCase {
  func test_givenBundledBook_whenLoaded_thenThousandsOfPositions() {
    XCTAssertGreaterThan(OpeningBook.shared.count, 3000)
  }

  func test_givenItalianGame_whenNamed_thenItalian() {
    var session = GameSession()
    for m in ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"] { session.apply(uci: m) }
    XCTAssertEqual(OpeningBook.shared.name(of: session)?.name, "Italian Game")
    XCTAssertTrue(OpeningBook.shared.isBook(fenAfter: session.position.fen))
  }

  func test_givenMateOnMoveFour_whenChecked_thenNotBook() {
    var session = GameSession()
    for m in ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"] { session.apply(uci: m) }
    XCTAssertFalse(OpeningBook.shared.isBook(fenAfter: session.position.fen))
  }
}
