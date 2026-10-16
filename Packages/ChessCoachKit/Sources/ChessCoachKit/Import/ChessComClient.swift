import Foundation

public enum ChessComError: Error, Equatable, Sendable {
  case userNotFound
  case rateLimited
  case http(status: Int)
}

/// One player block of a chess.com game (`white` / `black`).
public struct ChessComPlayer: Codable, Sendable, Equatable {
  public var username: String
  public var rating: Int
  public var result: String
}

/// chess.com's own (CAPS2) accuracy; present only when the game was reviewed on chess.com.
public struct ChessComAccuracies: Codable, Sendable, Equatable {
  public var white: Double?
  public var black: Double?
}

/// A game object from `GET /pub/player/{u}/games/{YYYY}/{MM}` (`games[]`).
public struct ChessComGame: Codable, Sendable, Equatable {
  public var url: String
  public var pgn: String
  public var timeControl: String
  public var endTime: Int
  public var rated: Bool
  public var timeClass: String
  public var rules: String
  public var fen: String?
  public var initialSetup: String?
  public var white: ChessComPlayer
  public var black: ChessComPlayer
  public var accuracies: ChessComAccuracies?

  enum CodingKeys: String, CodingKey {
    case url, pgn, rated, rules, fen, white, black, accuracies
    case timeControl = "time_control"
    case endTime = "end_time"
    case timeClass = "time_class"
    case initialSetup = "initial_setup"
  }
}

public enum MonthResult: Sendable, Equatable {
  case notModified
  case games([ChessComGame], etag: String?)
}

/// Serial client for the chess.com Published-Data API. One request at a time; 429 backs off 2s, 4s, 8s.
public struct ChessComClient: Sendable {
  public static let defaultUserAgent = "ChessCoach-iOS (personal; github.com/rishi-zamvar/ChessCoach-iOS)"

  let http: HTTPClient
  let telemetry: Telemetry
  let userAgent: String
  let sleeper: @Sendable (Duration) async throws -> Void

  public init(
    http: HTTPClient = URLSessionHTTPClient(),
    telemetry: Telemetry,
    userAgent: String = ChessComClient.defaultUserAgent,
    sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.http = http
    self.telemetry = telemetry
    self.userAgent = userAgent
    self.sleeper = sleeper
  }

  /// Monthly archive URLs, oldest first (as chess.com returns them).
  public func archives(username: String, parent: StepContext? = nil) async throws -> [URL] {
    try await telemetry.step("import.archives", parent: parent) { ctx in
      let url = URL(string: "https://api.chess.com/pub/player/\(username.lowercased())/games/archives")!
      let response = try await fetch(url, etag: nil, ctx: ctx)
      struct Archives: Decodable { var archives: [String] }
      let urls = try JSONDecoder().decode(Archives.self, from: response.body).archives.compactMap(URL.init(string:))
      ctx.annotate("months", .int(urls.count))
      return urls
    }
  }

  /// One month of games. Sends `If-None-Match` when `etag` is given; 304 → `.notModified`.
  public func month(url: URL, etag: String?, parent: StepContext? = nil) async throws -> MonthResult {
    try await telemetry.step("import.fetch", parent: parent, metadata: ["url": .string(url.absoluteString)]) { ctx in
      let response = try await fetch(url, etag: etag, ctx: ctx)
      if response.status == 304 {
        ctx.annotate("notModified", .bool(true))
        return .notModified
      }
      struct Month: Decodable { var games: [ChessComGame] }
      let games = try JSONDecoder().decode(Month.self, from: response.body).games
      ctx.annotate("games", .int(games.count))
      return .games(games, etag: response.headers["etag"])
    }
  }

  private func fetch(_ url: URL, etag: String?, ctx: StepContext) async throws -> HTTPResponse {
    var headers = ["User-Agent": userAgent, "Accept": "application/json"]
    if let etag { headers["If-None-Match"] = etag }
    var retries = 0
    while true {
      let response = try await http.get(url, headers: headers)
      ctx.annotate("status", .int(response.status))
      switch response.status {
      case 200, 304:
        return response
      case 404:
        throw ChessComError.userNotFound
      case 429:
        guard retries < 3 else { throw ChessComError.rateLimited }
        retries += 1
        ctx.annotate("retries", .int(retries))
        try await sleeper(.seconds(1 << retries))  // 2s, 4s, 8s
      default:
        throw ChessComError.http(status: response.status)
      }
    }
  }
}
