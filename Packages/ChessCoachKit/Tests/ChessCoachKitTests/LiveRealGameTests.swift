import XCTest
@testable import ChessCoachKit

/// Live: imports the user's real chess.com games and analyzes one. Run with LIVE=1.
final class LiveRealGameTests: XCTestCase {
  func test_givenRealChessComGames_whenImportedAndAnalyzed_thenLabelsAndExplanationsAreSane() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE"] == "1", "set LIVE=1")
    let telemetry = Telemetry(sinks: [])
    let importer = ChessComImporter(client: ChessComClient(telemetry: telemetry), telemetry: telemetry)
    let batch = try await importer.importGames(username: "Zammy009", knownURLs: [], monthETags: [:], maxMonths: 1)
    XCTAssertGreaterThan(batch.games.count, 10)
    let index = Int(ProcessInfo.processInfo.environment["GAME"] ?? "0") ?? 0
    let game = batch.games.sorted { $0.endedAt > $1.endedAt }[index]
    let host = EngineHost(assets: EngineHostTests.assets)
    let analyzer = GameAnalyzer(host: host, telemetry: telemetry, depth: 12)
    var out = ""
    func log(_ line: String) { out += line + "\n" }
    let start = Date()
    let a = try await analyzer.analyze(gameID: game.id, pgn: game.pgn, userColor: game.userColor, timeControl: game.timeControl)
    log("GAME \(game.id) \(game.white) vs \(game.black) \(game.result) user=\(game.userColor) opening=\(a.openingName ?? "-") in \(Int(Date().timeIntervalSince(start)))s")
    log("ACC white=\(a.accuracyWhite ?? -1) black=\(a.accuracyBlack ?? -1) chesscom=\(game.chessComAccuracy ?? -1)")
    for m in a.moves where m.label != .book && m.label != .best && m.label != .excellent && m.label != .good {
      log("PLY \(m.ply) \(m.color) \(m.san) [\(m.label.rawValue)] loss=\(String(format: "%.2f", m.loss)) type=\(m.mistakeType?.rawValue ?? "-") :: \(m.explanation)")
    }
    for m in a.moves { XCTAssertTrue(m.facts.map { Explainer.isGrounded(m.explanation, in: $0) } ?? true, "ungrounded: \(m.explanation)") }
    // stdout belongs to the engine (chesskit-engine dup2s it), so write a file.
    try out.write(toFile: "/tmp/cc-live-game.txt", atomically: true, encoding: .utf8)
    await host.shutdown()
  }
}
