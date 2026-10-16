import Foundation

/// A chess.com game normalised for the app (user-relative colour, PGN-style result).
public struct ImportedGame: Sendable, Equatable {
  /// The chess.com game URL (stable, unique).
  public var id: String
  public var pgn: String
  public var white: String
  public var black: String
  public var whiteElo: Int
  public var blackElo: Int
  /// "white" or "black".
  public var userColor: String
  /// "1-0", "0-1" or "1/2-1/2".
  public var result: String
  /// "checkmate", "resignation", "timeout", "abandoned", or the draw reason ("stalemate", "agreed", …).
  public var termination: String
  public var timeControl: String
  public var timeClass: String
  public var endedAt: Date
  /// The user's chess.com (CAPS2) accuracy, when the game was reviewed there.
  public var chessComAccuracy: Double?
}

public struct ImportBatch: Sendable, Equatable {
  public var games: [ImportedGame]
  /// Month archive URL → ETag, merged with the input map. Persist and pass back next time.
  public var etags: [String: String]
}

/// Walks a user's monthly archives newest-first, serially, and keeps standard, non-daily games.
public struct ChessComImporter: Sendable {
  static let standardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  let client: ChessComClient
  let telemetry: Telemetry

  public init(client: ChessComClient, telemetry: Telemetry) {
    self.client = client
    self.telemetry = telemetry
  }

  /// Past months that already have a stored ETag are immutable and skipped. The two newest archives
  /// are always revalidated with `If-None-Match` (the second covers games finished at month rollover).
  public func importGames(
    username: String, knownURLs: Set<String>, monthETags: [String: String], maxMonths: Int = 3
  ) async throws -> ImportBatch {
    try await telemetry.step("import.run", metadata: ["user": .string(username.lowercased())]) { run in
      let months = Array(try await client.archives(username: username, parent: run).reversed().prefix(maxMonths))
      var etags = monthETags
      var seen = knownURLs
      var games: [ImportedGame] = []
      run.progress(done: 0, total: months.count)
      for (index, monthURL) in months.enumerated() {
        let key = monthURL.absoluteString
        let live = index < 2
        try await telemetry.step("import.month", parent: run, metadata: ["url": .string(key)]) { ctx in
          if !live, etags[key] != nil {
            ctx.annotate("cached", .bool(true))
            return
          }
          switch try await client.month(url: monthURL, etag: live ? etags[key] : nil, parent: ctx) {
          case .notModified:
            ctx.annotate("notModified", .bool(true))
          case .games(let raw, let etag):
            if let etag { etags[key] = etag }
            var kept = 0
            var skipped = 0
            for game in raw {
              guard !seen.contains(game.url), let imported = Self.convert(game, username: username) else {
                skipped += 1
                continue
              }
              seen.insert(game.url)
              games.append(imported)
              kept += 1
            }
            ctx.annotate("kept", .int(kept))
            ctx.annotate("skipped", .int(skipped))
          }
        }
        run.progress(done: index + 1, total: months.count)
      }
      run.annotate("games", .int(games.count))
      return ImportBatch(games: games, etags: etags)
    }
  }

  /// Applies the import filters and maps a chess.com game; nil when the game is dropped.
  static func convert(_ game: ChessComGame, username: String) -> ImportedGame? {
    let user = username.lowercased()
    let userColor: String
    if game.white.username.lowercased() == user {
      userColor = "white"
    } else if game.black.username.lowercased() == user {
      userColor = "black"
    } else {
      return nil
    }
    guard game.rules == "chess", game.timeClass != "daily", isStandardStart(game), plyCount(pgn: game.pgn) > 2 else {
      return nil
    }

    let result: String
    let termination: String
    if game.white.result == "win" {
      result = "1-0"
      termination = reason(game.black.result)
    } else if game.black.result == "win" {
      result = "0-1"
      termination = reason(game.white.result)
    } else {
      result = "1/2-1/2"
      termination = game.white.result  // draws carry the same code on both sides
    }
    return ImportedGame(
      id: game.url, pgn: game.pgn,
      white: game.white.username, black: game.black.username,
      whiteElo: game.white.rating, blackElo: game.black.rating,
      userColor: userColor, result: result, termination: termination,
      timeControl: game.timeControl, timeClass: game.timeClass,
      endedAt: Date(timeIntervalSince1970: TimeInterval(game.endTime)),
      chessComAccuracy: userColor == "white" ? game.accuracies?.white : game.accuracies?.black)
  }

  private static func reason(_ loserResult: String) -> String {
    switch loserResult {
    case "checkmated": "checkmate"
    case "resigned": "resignation"
    default: loserResult  // timeout, abandoned, variant-specific codes
    }
  }

  static func isStandardStart(_ game: ChessComGame) -> Bool {
    if let setup = game.initialSetup, !setup.isEmpty, setup != standardFEN { return false }
    if let match = game.pgn.firstMatch(of: /\[FEN "([^"]*)"\]/), String(match.1) != standardFEN { return false }
    return true
  }

  /// Counts SAN moves in the movetext (headers, `{…}` comments, `(…)` variations, NAGs, numbers, result stripped).
  static func plyCount(pgn: String) -> Int {
    let movetext = pgn.split(separator: "\n").filter { !$0.hasPrefix("[") }.joined(separator: " ")
      .replacing(/\{[^}]*\}/, with: " ")
      .replacing(/\([^)]*\)/, with: " ")
    return movetext.split(whereSeparator: \.isWhitespace).filter { token in
      !(token.wholeMatch(of: /\d+\.+|\$\d+|1-0|0-1|1\/2-1\/2|\*/) != nil)
    }.count
  }
}
