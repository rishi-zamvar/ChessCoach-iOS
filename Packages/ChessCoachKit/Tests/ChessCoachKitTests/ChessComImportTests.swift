import XCTest
@testable import ChessCoachKit

/// Scripted transport: responses are served in order; every request is recorded.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
  private let lock = NSLock()
  private var script: [HTTPResponse]
  private(set) var requests: [(url: URL, headers: [String: String])] = []

  init(_ script: [HTTPResponse]) { self.script = script }

  func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
    lock.withLock {
      requests.append((url, headers))
      return script.isEmpty ? HTTPResponse(status: 500) : script.removeFirst()
    }
  }

  var urls: [String] { lock.withLock { requests.map(\.url.absoluteString) } }
}

final class SleepRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Duration] = []
  var delays: [Duration] { lock.withLock { storage } }
  func sleep(_ d: Duration) async throws { lock.withLock { storage.append(d) } }
}

final class ChessComImportTests: XCTestCase {
  // Real response of GET /pub/player/zammy009/games/2026/10 (2026-10-16), trimmed to 4 games:
  // [0] live rapid, user black, lost on time, reviewed (accuracies);
  // [1] live rapid, user white, won by checkmate (4 moves);
  // [2] live rapid, 1-ply abandoned game; [3] daily vs Coach (time_control "-", PGN shortened).
  static let monthJSON = ##"""
    {
     "games": [
      {
       "url": "https://www.chess.com/game/live/185028600498",
       "pgn": "[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2026.10.08\"]\n[Round \"-\"]\n[White \"Brokusky\"]\n[Black \"Zammy009\"]\n[Result \"1-0\"]\n[CurrentPosition \"8/1pk2bpp/p1pb4/4r1B1/4PnPP/1PN2P2/1PPR4/2K1R3 b - - 2 21\"]\n[Timezone \"UTC\"]\n[ECO \"C41\"]\n[ECOUrl \"https://www.chess.com/openings/Philidor-Defense\"]\n[UTCDate \"2026.10.08\"]\n[UTCTime \"21:19:29\"]\n[WhiteElo \"343\"]\n[BlackElo \"190\"]\n[TimeControl \"600\"]\n[Termination \"Brokusky won on time\"]\n[StartTime \"21:19:29\"]\n[EndDate \"2026.10.08\"]\n[EndTime \"21:37:21\"]\n[Link \"https://www.chess.com/game/live/185028600498\"]\n\n1. e4 {[%clk 0:09:53.4]} 1... e5 {[%clk 0:09:55.7]} 2. Nf3 {[%clk 0:09:51.9]} 2... d6 {[%clk 0:09:43.5]} 3. Bb5+ {[%clk 0:09:41.7]} 3... Bd7 {[%clk 0:09:35.9]} 4. Nc3 {[%clk 0:09:30.3]} 4... a6 {[%clk 0:09:19.9]} 5. Ba4 {[%clk 0:09:27.1]} 5... Nf6 {[%clk 0:08:55.4]} 6. d4 {[%clk 0:09:19.4]} 6... c6 {[%clk 0:08:36.2]} 7. dxe5 {[%clk 0:08:58.4]} 7... dxe5 {[%clk 0:08:14]} 8. Nxe5 {[%clk 0:08:41.1]} 8... Bg4 {[%clk 0:07:46.5]} 9. Qxd8+ {[%clk 0:08:30.8]} 9... Kxd8 {[%clk 0:07:36]} 10. Bg5 {[%clk 0:08:14.2]} 10... Bd6 {[%clk 0:06:31]} 11. Nxf7+ {[%clk 0:07:31.1]} 11... Kc7 {[%clk 0:05:45.2]} 12. Nxh8 {[%clk 0:07:23.8]} 12... Nbd7 {[%clk 0:04:21.5]} 13. Nf7 {[%clk 0:07:18.6]} 13... Re8 {[%clk 0:04:09.8]} 14. f3 {[%clk 0:07:09.2]} 14... Be6 {[%clk 0:03:57.3]} 15. Bb3 {[%clk 0:04:59.7]} 15... Nc5 {[%clk 0:02:30.3]} 16. O-O-O {[%clk 0:04:37.6]} 16... Nxb3+ {[%clk 0:01:54.4]} 17. axb3 {[%clk 0:04:25.3]} 17... Bxf7 {[%clk 0:01:49.7]} 18. h4 {[%clk 0:03:49.6]} 18... Re5 {[%clk 0:00:58.9]} 19. Rhe1 {[%clk 0:03:08.1]} 19... Nh5 {[%clk 0:00:40.3]} 20. g4 {[%clk 0:02:39.1]} 20... Nf4 {[%clk 0:00:22.8]} 21. Rd2 {[%clk 0:02:17.6]} 1-0\n",
       "time_control": "600",
       "end_time": 1791495441,
       "rated": true,
       "accuracies": {
        "white": 83.73,
        "black": 74.03
       },
       "tcn": "mC0KgvZRfH6ZbsWOHy!TlBYQBKRKvKZEd787cM9RK17Y1?5Z?148nvESyrZIecIrirS1pF8KheTNoENDdl",
       "uuid": "f2c72c2f-c35d-11f1-8c7a-e0caaf01000f",
       "initial_setup": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
       "fen": "8/1pk2bpp/p1pb4/4r1B1/4PnPP/1PN2P2/1PPR4/2K1R3 b - - 2 21",
       "time_class": "rapid",
       "rules": "chess",
       "white": {
        "rating": 343,
        "result": "win",
        "@id": "https://api.chess.com/pub/player/brokusky",
        "username": "Brokusky",
        "uuid": "3df9b3d0-b96a-11f1-84bf-07a1baa4a2f3"
       },
       "black": {
        "rating": 190,
        "result": "timeout",
        "@id": "https://api.chess.com/pub/player/zammy009",
        "username": "Zammy009",
        "uuid": "d0432f3a-c35d-11f1-aba4-3dc2ae26cc51"
       },
       "eco": "https://www.chess.com/openings/Philidor-Defense"
      },
      {
       "url": "https://www.chess.com/game/live/185234473596",
       "pgn": "[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2026.10.12\"]\n[Round \"-\"]\n[White \"Zammy009\"]\n[Black \"JINX_BINGA\"]\n[Result \"1-0\"]\n[CurrentPosition \"r1bqkbnr/p1pppBpp/1p6/8/1n2P3/5Q2/PPPP1PPP/RNB1K1NR b KQkq - 0 4\"]\n[Timezone \"UTC\"]\n[ECO \"B00\"]\n[ECOUrl \"https://www.chess.com/openings/Nimzowitsch-Defense\"]\n[UTCDate \"2026.10.12\"]\n[UTCTime \"22:05:23\"]\n[WhiteElo \"178\"]\n[BlackElo \"109\"]\n[TimeControl \"600\"]\n[Termination \"Zammy009 won by checkmate\"]\n[StartTime \"22:05:23\"]\n[EndDate \"2026.10.12\"]\n[EndTime \"22:06:19\"]\n[Link \"https://www.chess.com/game/live/185234473596\"]\n\n1. e4 {[%clk 0:09:58.4]} 1... Nc6 {[%clk 0:09:52.3]} 2. Qf3 {[%clk 0:09:56.8]} 2... Nb4 {[%clk 0:09:40]} 3. Bc4 {[%clk 0:09:54.7]} 3... b6 {[%clk 0:09:14.2]} 4. Bxf7# {[%clk 0:09:52.9]} 1-0\n",
       "time_control": "600",
       "end_time": 1791842779,
       "rated": true,
       "tcn": "mC5QdvQzfAXPA1",
       "uuid": "059ab489-c689-11f1-94d8-40057201000f",
       "initial_setup": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
       "fen": "r1bqkbnr/p1pppBpp/1p6/8/1n2P3/5Q2/PPPP1PPP/RNB1K1NR b KQkq - 0 4",
       "time_class": "rapid",
       "rules": "chess",
       "white": {
        "rating": 178,
        "result": "win",
        "@id": "https://api.chess.com/pub/player/zammy009",
        "username": "Zammy009",
        "uuid": "d0432f3a-c35d-11f1-aba4-3dc2ae26cc51"
       },
       "black": {
        "rating": 109,
        "result": "checkmated",
        "@id": "https://api.chess.com/pub/player/jinx_binga",
        "username": "JINX_BINGA",
        "uuid": "62d0c0a0-8935-11f1-99d9-d7683e6c200e"
       },
       "eco": "https://www.chess.com/openings/Nimzowitsch-Defense"
      },
      {
       "url": "https://www.chess.com/game/live/185171473454",
       "pgn": "[Event \"Live Chess\"]\n[Site \"Chess.com\"]\n[Date \"2026.10.11\"]\n[Round \"-\"]\n[White \"Zammy009\"]\n[Black \"solojayhairz\"]\n[Result \"1-0\"]\n[CurrentPosition \"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1\"]\n[Timezone \"UTC\"]\n[ECO \"B00\"]\n[ECOUrl \"https://www.chess.com/openings/Kings-Pawn-Opening\"]\n[UTCDate \"2026.10.11\"]\n[UTCTime \"17:27:24\"]\n[WhiteElo \"178\"]\n[BlackElo \"127\"]\n[TimeControl \"600\"]\n[Termination \"Zammy009 won - game abandoned\"]\n[StartTime \"17:27:24\"]\n[EndDate \"2026.10.11\"]\n[EndTime \"17:28:28\"]\n[Link \"https://www.chess.com/game/live/185171473454\"]\n\n1. e4 {[%clk 0:09:59.2]} 1-0\n",
       "time_control": "600",
       "end_time": 1791739708,
       "rated": true,
       "tcn": "mC",
       "uuid": "0618c2d7-c599-11f1-91e9-76c88101000f",
       "initial_setup": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
       "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
       "time_class": "rapid",
       "rules": "chess",
       "white": {
        "rating": 178,
        "result": "win",
        "@id": "https://api.chess.com/pub/player/zammy009",
        "username": "Zammy009",
        "uuid": "d0432f3a-c35d-11f1-aba4-3dc2ae26cc51"
       },
       "black": {
        "rating": 127,
        "result": "abandoned",
        "@id": "https://api.chess.com/pub/player/solojayhairz",
        "username": "solojayhairz",
        "uuid": "9e4231d8-1193-11f1-a117-b759c27feb38"
       },
       "eco": "https://www.chess.com/openings/Kings-Pawn-Opening"
      },
      {
       "url": "https://www.chess.com/game/daily/268243528",
       "pgn": "[Event \"Play vs Coach\"]\n[Site \"Chess.com\"]\n[Date \"2026.10.09\"]\n[Round \"-\"]\n[White \"Zammy009\"]\n[Black \"Coach-Vishy\"]\n[Result \"1/2-1/2\"]\n[CurrentPosition \"8/4R3/6Nk/3Q4/5K2/1P5P/PP6/6R1 b - - 8 39\"]\n[Timezone \"UTC\"]\n[ECO \"B01\"]\n[ECOUrl \"https://www.chess.com/openings/Scandinavian-Defense-Mieses-Kotrc-Gubinsky-Melts-Defense-4.d4\"]\n[UTCDate \"2026.10.09\"]\n[UTCTime \"21:03:26\"]\n[WhiteElo \"223\"]\n[BlackElo \"400\"]\n[TimeControl \"-\"]\n[Termination \"Game drawn by stalemate\"]\n[StartTime \"21:03:26\"]\n[EndDate \"2026.10.09\"]\n[EndTime \"21:14:57\"]\n[Link \"https://www.chess.com/game/daily/268243528\"]\n\n1. e4 {[%clk 1:00:00]} 1... d5 2. exd5 Qxd5 1/2-1/2\n",
       "time_control": "-",
       "end_time": 1791580497,
       "rated": false,
       "tcn": "mCZJCJ7JbsJRlBRKBK5QcD3Vdb?3ftVNt3!VgvQ5vF2UegVEnv5OpxEKDK6ZKYOYbd0Kfe9IgpI9eKZS3UWOUNXHN181sHSxoxOHdZ90K01TZYTMpw4yvDyD0KMVwDHzYRV3agzrkr3?FU?!R7!2K02V7J",
       "uuid": "df1aeabc-c424-11f1-95f5-d5302bb66a01",
       "initial_setup": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
       "fen": "8/4R3/6Nk/3Q4/5K2/1P5P/PP6/6R1 b - - 8 39",
       "start_time": 1791579806,
       "time_class": "daily",
       "rules": "chess",
       "white": {
        "rating": 223,
        "result": "stalemate",
        "@id": "https://api.chess.com/pub/player/zammy009",
        "username": "Zammy009",
        "uuid": "d0432f3a-c35d-11f1-aba4-3dc2ae26cc51"
       },
       "black": {
        "rating": 400,
        "result": "stalemate",
        "@id": "https://api.chess.com/pub/player/coach-vishy",
        "username": "Coach-Vishy",
        "uuid": "63c785be-d537-11f0-95a0-8fbb60516084"
       }
      }
     ]
    }
    """##

  static let archivesJSON = #"{"archives":["https://api.chess.com/pub/player/zammy009/games/2026/08","https://api.chess.com/pub/player/zammy009/games/2026/09","https://api.chess.com/pub/player/zammy009/games/2026/10"]}"#
  static let oct = "https://api.chess.com/pub/player/zammy009/games/2026/10"
  static let sep = "https://api.chess.com/pub/player/zammy009/games/2026/09"
  static let aug = "https://api.chess.com/pub/player/zammy009/games/2026/08"

  static func ok(_ json: String, etag: String? = nil) -> HTTPResponse {
    HTTPResponse(status: 200, headers: etag.map { ["ETag": $0] } ?? [:], body: Data(json.utf8))
  }

  static func realGames() throws -> [ChessComGame] {
    struct Month: Decodable { var games: [ChessComGame] }
    return try JSONDecoder().decode(Month.self, from: Data(monthJSON.utf8)).games
  }

  static func monthBody(_ games: [ChessComGame]) throws -> String {
    struct Month: Encodable { var games: [ChessComGame] }
    return String(decoding: try JSONEncoder().encode(Month(games: games)), as: UTF8.self)
  }

  func makeImporter(_ http: FakeHTTPClient, sink: MemorySink = MemorySink(), sleeper: SleepRecorder = SleepRecorder())
    -> ChessComImporter
  {
    let telemetry = Telemetry(sinks: [sink])
    let client = ChessComClient(http: http, telemetry: telemetry, sleeper: { try await sleeper.sleep($0) })
    return ChessComImporter(client: client, telemetry: telemetry)
  }

  // MARK: Client

  func test_givenArchivesResponse_whenFetched_thenReturnsURLsAndSendsUserAgentToLowercasedPath() async throws {
    let http = FakeHTTPClient([Self.ok(Self.archivesJSON)])
    let client = ChessComClient(http: http, telemetry: Telemetry(sinks: []))
    let urls = try await client.archives(username: "Zammy009")
    XCTAssertEqual(urls.map(\.absoluteString), [Self.aug, Self.sep, Self.oct])
    XCTAssertEqual(http.urls, ["https://api.chess.com/pub/player/zammy009/games/archives"])
    XCTAssertEqual(http.requests[0].headers["User-Agent"], "ChessCoach-iOS (personal; github.com/rishi-zamvar/ChessCoach-iOS)")
    XCTAssertNil(http.requests[0].headers["If-None-Match"])
  }

  func test_givenRealMonthFixture_whenFetched_thenDecodesAllFieldsAndETag() async throws {
    let http = FakeHTTPClient([Self.ok(Self.monthJSON, etag: "W/\"abc\"")])
    let client = ChessComClient(http: http, telemetry: Telemetry(sinks: []))
    guard case .games(let games, let etag) = try await client.month(url: URL(string: Self.oct)!, etag: nil) else {
      return XCTFail("expected games")
    }
    XCTAssertEqual(etag, "W/\"abc\"")
    XCTAssertEqual(games.count, 4)
    let g = games[0]
    XCTAssertEqual(g.url, "https://www.chess.com/game/live/185028600498")
    XCTAssertEqual(g.timeControl, "600")
    XCTAssertEqual(g.timeClass, "rapid")
    XCTAssertEqual(g.rules, "chess")
    XCTAssertEqual(g.endTime, 1_791_495_441)
    XCTAssertTrue(g.rated)
    XCTAssertEqual(g.initialSetup, ChessComImporter.standardFEN)
    XCTAssertEqual(g.black, ChessComPlayer(username: "Zammy009", rating: 190, result: "timeout"))
    XCTAssertEqual(g.accuracies, ChessComAccuracies(white: 83.73, black: 74.03))
    XCTAssertNil(games[1].accuracies)
    XCTAssertEqual(games[3].timeControl, "-")
  }

  func test_given304_whenMonthFetchedWithETag_thenNotModifiedAndIfNoneMatchSent() async throws {
    let http = FakeHTTPClient([HTTPResponse(status: 304)])
    let client = ChessComClient(http: http, telemetry: Telemetry(sinks: []))
    let result = try await client.month(url: URL(string: Self.oct)!, etag: "W/\"abc\"")
    XCTAssertEqual(result, .notModified)
    XCTAssertEqual(http.requests[0].headers["If-None-Match"], "W/\"abc\"")
  }

  func test_given429Twice_whenFetched_thenBacksOff2sThen4sAndSucceeds() async throws {
    let http = FakeHTTPClient([HTTPResponse(status: 429), HTTPResponse(status: 429), Self.ok(Self.archivesJSON)])
    let sleeper = SleepRecorder()
    let client = ChessComClient(http: http, telemetry: Telemetry(sinks: []), sleeper: { try await sleeper.sleep($0) })
    let urls = try await client.archives(username: "zammy009")
    XCTAssertEqual(urls.count, 3)
    XCTAssertEqual(sleeper.delays, [.seconds(2), .seconds(4)])
  }

  func test_given429Always_whenFetched_thenThreeRetriesThenRateLimited() async {
    let http = FakeHTTPClient(Array(repeating: HTTPResponse(status: 429), count: 5))
    let sleeper = SleepRecorder()
    let client = ChessComClient(http: http, telemetry: Telemetry(sinks: []), sleeper: { try await sleeper.sleep($0) })
    do {
      _ = try await client.archives(username: "zammy009")
      XCTFail("expected rateLimited")
    } catch {
      XCTAssertEqual(error as? ChessComError, .rateLimited)
    }
    XCTAssertEqual(sleeper.delays, [.seconds(2), .seconds(4), .seconds(8)])
    XCTAssertEqual(http.requests.count, 4)
  }

  func test_given404_whenArchivesFetched_thenUserNotFound() async {
    let http = FakeHTTPClient([HTTPResponse(status: 404, body: Data(#"{"code":0,"message":"User not found"}"#.utf8))])
    let client = ChessComClient(http: http, telemetry: Telemetry(sinks: []))
    do {
      _ = try await client.archives(username: "nobody")
      XCTFail("expected userNotFound")
    } catch {
      XCTAssertEqual(error as? ChessComError, .userNotFound)
    }
  }

  // MARK: Mapping & filters

  func test_givenUserAsBlackLosingOnTime_whenConverted_thenZeroOneTimeoutWithBlackAccuracy() throws {
    let g = try XCTUnwrap(ChessComImporter.convert(try Self.realGames()[0], username: "zammy009"))
    XCTAssertEqual(g.id, "https://www.chess.com/game/live/185028600498")
    XCTAssertEqual(g.userColor, "black")
    XCTAssertEqual(g.result, "1-0")
    XCTAssertEqual(g.termination, "timeout")
    XCTAssertEqual(g.white, "Brokusky")
    XCTAssertEqual(g.whiteElo, 343)
    XCTAssertEqual(g.blackElo, 190)
    XCTAssertEqual(g.chessComAccuracy, 74.03)
    XCTAssertEqual(g.timeControl, "600")
    XCTAssertEqual(g.timeClass, "rapid")
    XCTAssertEqual(g.endedAt, Date(timeIntervalSince1970: 1_791_495_441))
  }

  func test_givenUserAsWhiteWinningByMate_whenConvertedWithUppercaseName_thenOneZeroCheckmate() throws {
    let g = try XCTUnwrap(ChessComImporter.convert(try Self.realGames()[1], username: "ZAMMY009"))
    XCTAssertEqual(g.userColor, "white")
    XCTAssertEqual(g.result, "1-0")
    XCTAssertEqual(g.termination, "checkmate")
    XCTAssertNil(g.chessComAccuracy)
  }

  func test_givenLossAndDrawCodes_whenConverted_thenResultAndTerminationMapped() throws {
    var game = try Self.realGames()[1]  // user is white
    let cases: [(white: String, black: String, result: String, termination: String)] = [
      ("resigned", "win", "0-1", "resignation"),
      ("checkmated", "win", "0-1", "checkmate"),
      ("abandoned", "win", "0-1", "abandoned"),
      ("win", "resigned", "1-0", "resignation"),
      ("agreed", "agreed", "1/2-1/2", "agreed"),
      ("repetition", "repetition", "1/2-1/2", "repetition"),
      ("stalemate", "stalemate", "1/2-1/2", "stalemate"),
      ("insufficient", "insufficient", "1/2-1/2", "insufficient"),
      ("50move", "50move", "1/2-1/2", "50move"),
      ("timevsinsufficient", "timevsinsufficient", "1/2-1/2", "timevsinsufficient"),
    ]
    for c in cases {
      game.white.result = c.white
      game.black.result = c.black
      let g = try XCTUnwrap(ChessComImporter.convert(game, username: "zammy009"))
      XCTAssertEqual(g.result, c.result, "\(c)")
      XCTAssertEqual(g.termination, c.termination, "\(c)")
    }
  }

  func test_givenFilteredGames_whenConverted_thenVariantDailyAbortedCustomFENAndStrangerDropped() throws {
    let games = try Self.realGames()
    XCTAssertNil(ChessComImporter.convert(games[2], username: "zammy009"), "1-ply abandoned game")
    XCTAssertNil(ChessComImporter.convert(games[3], username: "zammy009"), "daily game")

    var variant = games[1]
    variant.rules = "chess960"
    XCTAssertNil(ChessComImporter.convert(variant, username: "zammy009"))

    let custom = "4k3/8/8/8/8/8/8/4K2R w K - 0 1"
    var setup = games[1]
    setup.initialSetup = custom
    XCTAssertNil(ChessComImporter.convert(setup, username: "zammy009"))

    var fenTag = games[1]
    fenTag.pgn = fenTag.pgn.replacingOccurrences(of: "[Event", with: "[SetUp \"1\"]\n[FEN \"\(custom)\"]\n[Event")
    XCTAssertNil(ChessComImporter.convert(fenTag, username: "zammy009"))

    XCTAssertNil(ChessComImporter.convert(games[1], username: "someoneelse"))
    XCTAssertNotNil(ChessComImporter.convert(games[1], username: "zammy009"))
  }

  func test_givenRealPGNs_whenPliesCounted_thenCommentsAndNumbersIgnored() throws {
    let games = try Self.realGames()
    XCTAssertEqual(ChessComImporter.plyCount(pgn: games[0].pgn), 41)
    XCTAssertEqual(ChessComImporter.plyCount(pgn: games[1].pgn), 7)
    XCTAssertEqual(ChessComImporter.plyCount(pgn: games[2].pgn), 1)
  }

  // MARK: Importer

  func test_givenThreeMonths_whenImported_thenNewestFirstFilteredDedupedAndETagsStored() async throws {
    let games = try Self.realGames()
    var older = games[0]
    older.url = "https://www.chess.com/game/live/1"
    let http = FakeHTTPClient([
      Self.ok(Self.archivesJSON),
      Self.ok(Self.monthJSON, etag: "oct-1"),
      Self.ok(try Self.monthBody([games[1], older]), etag: "sep-1"),  // games[1] repeats: deduped
      Self.ok(try Self.monthBody([]), etag: "aug-1"),
    ])
    let sink = MemorySink()
    let batch = try await makeImporter(http, sink: sink).importGames(
      username: "Zammy009", knownURLs: [games[0].url], monthETags: [:])
    XCTAssertEqual(http.urls.dropFirst(), [Self.oct, Self.sep, Self.aug])
    XCTAssertEqual(batch.games.map(\.id), [games[1].url, older.url])
    XCTAssertEqual(batch.etags, [Self.oct: "oct-1", Self.sep: "sep-1", Self.aug: "aug-1"])

    let monthFinishes = sink.events(named: "import.month").filter { $0.phase == .finish }
    XCTAssertEqual(monthFinishes.count, 3)
    XCTAssertEqual(monthFinishes[0].metadata["kept"], .int(1))
    XCTAssertEqual(monthFinishes[0].metadata["skipped"], .int(3))
    XCTAssertEqual(monthFinishes[1].metadata["kept"], .int(1))
    XCTAssertEqual(monthFinishes[1].metadata["skipped"], .int(1))
    let run = sink.events(named: "import.run")
    XCTAssertEqual(run.first?.phase, .start)
    XCTAssertEqual(run.last?.phase, .finish)
    XCTAssertEqual(run.filter { $0.phase == .progress }.map(\.done), [0, 1, 2, 3])
    XCTAssertEqual(run.last?.metadata["games"], .int(2))
    XCTAssertEqual(sink.events(named: "import.archives").last?.phase, .finish)
    XCTAssertEqual(sink.events(named: "import.fetch").filter { $0.phase == .finish }.count, 3)
    XCTAssertTrue(sink.events(named: "import.month").allSatisfy { $0.runID == run[0].runID })
  }

  func test_givenStoredETags_whenReimported_thenLiveMonthsRevalidatedAndOldMonthSkipped() async throws {
    let http = FakeHTTPClient([Self.ok(Self.archivesJSON), HTTPResponse(status: 304), HTTPResponse(status: 304)])
    let etags = [Self.oct: "oct-1", Self.sep: "sep-1", Self.aug: "aug-1"]
    let sink = MemorySink()
    let batch = try await makeImporter(http, sink: sink).importGames(
      username: "zammy009", knownURLs: [], monthETags: etags)
    XCTAssertEqual(batch.games, [])
    XCTAssertEqual(batch.etags, etags)
    XCTAssertEqual(http.urls.dropFirst(), [Self.oct, Self.sep])
    XCTAssertEqual(http.requests[1].headers["If-None-Match"], "oct-1")
    XCTAssertEqual(http.requests[2].headers["If-None-Match"], "sep-1")
    let months = sink.events(named: "import.month").filter { $0.phase == .finish }
    XCTAssertEqual(months.map { $0.metadata["notModified"] }, [.bool(true), .bool(true), nil])
    XCTAssertEqual(months[2].metadata["cached"], .bool(true))
  }

  func test_givenMaxMonthsOne_whenImported_thenOnlyNewestMonthFetched() async throws {
    let http = FakeHTTPClient([Self.ok(Self.archivesJSON), Self.ok(Self.monthJSON, etag: "oct-2")])
    let batch = try await makeImporter(http).importGames(
      username: "zammy009", knownURLs: [], monthETags: [:], maxMonths: 1)
    XCTAssertEqual(http.urls.dropFirst(), [Self.oct])
    XCTAssertEqual(batch.games.count, 2)
  }

  func test_givenUnknownUser_whenImported_thenUserNotFoundAndRunFails() async {
    let http = FakeHTTPClient([HTTPResponse(status: 404)])
    let sink = MemorySink()
    do {
      _ = try await makeImporter(http, sink: sink).importGames(username: "nobody", knownURLs: [], monthETags: [:])
      XCTFail("expected userNotFound")
    } catch {
      XCTAssertEqual(error as? ChessComError, .userNotFound)
    }
    XCTAssertEqual(sink.events(named: "import.run").last?.phase, .fail)
  }
}
