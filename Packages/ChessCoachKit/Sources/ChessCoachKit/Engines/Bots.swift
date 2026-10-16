import Foundation

/// Source of randomness (seedable in tests).
public protocol RandomSource: Sendable {
  /// Uniform value in [0, 1).
  func next() -> Double
}

public struct SystemRandom: RandomSource {
  public init() {}
  public func next() -> Double { Double.random(in: 0..<1) }
}

/// Deterministic generator (SplitMix64) for tests and replays.
public final class SeededRandom: RandomSource, @unchecked Sendable {
  private var state: UInt64
  private let lock = NSLock()

  public init(seed: UInt64) { state = seed }

  public func next() -> Double {
    lock.withLock {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      z = z ^ (z >> 31)
      return Double(z >> 11) / Double(1 << 53)
    }
  }
}

/// An opponent that picks moves.
public protocol BotPlayer: Sendable {
  var name: String { get }
  var rating: Int { get }
  /// Identifier stored with saved games, e.g. `maia-1100`, `stockfish-3`.
  var kind: String { get }
  /// Returns the bot's move in UCI for the position `fen`.
  func move(fen: String) async throws -> String
}

/// Human-like opponent: samples Maia's move probabilities at a rating.
public struct MaiaBot: BotPlayer {
  public let host: EngineHost
  public let rating: Int
  /// 1 = sample Maia's distribution as is; 0 = always its top move.
  public let temperature: Double
  let random: RandomSource
  let telemetry: Telemetry

  public init(host: EngineHost, rating: Int = 1100, temperature: Double = 1.0, random: RandomSource = SystemRandom(), telemetry: Telemetry) {
    self.host = host
    self.rating = rating
    self.temperature = temperature
    self.random = random
    self.telemetry = telemetry
  }

  public var name: String { "Maia \(rating)" }
  public var kind: String { "maia-\(rating)" }

  public func move(fen: String) async throws -> String {
    try await telemetry.step("bot.move", metadata: ["kind": .string(kind)]) { ctx in
      let result = try await host.search(.maia(rating: rating), fen: fen, limit: .nodes(1))
      let chosen = Self.sample(result.policy, temperature: temperature, random: random) ?? result.bestMove
      ctx.annotate("move", .string(chosen))
      ctx.annotate("prob", .double(result.policy[chosen] ?? 0))
      return chosen
    }
  }

  /// Picks a move from `policy` with temperature scaling. nil when the policy is empty.
  static func sample(_ policy: [String: Double], temperature: Double, random: RandomSource) -> String? {
    guard !policy.isEmpty else { return nil }
    let ordered = policy.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    if temperature <= 0.01 { return ordered.first?.key }
    let weights = ordered.map { pow(max($0.value, 1e-9), 1 / temperature) }
    let total = weights.reduce(0, +)
    var pick = random.next() * total
    for (entry, weight) in zip(ordered, weights) {
      pick -= weight
      if pick < 0 { return entry.key }
    }
    return ordered.last?.key
  }
}

/// Stockfish strength levels with approximate ratings.
public struct BotLevel: Sendable, Equatable, Hashable, Identifiable {
  public var id: Int { level }
  public let level: Int
  public let skill: Int
  public let depth: Int
  public let movetimeMs: Int
  public let displayRating: Int

  public static let all: [BotLevel] = [
    .init(level: 1, skill: 0, depth: 1, movetimeMs: 50, displayRating: 400),
    .init(level: 2, skill: 2, depth: 2, movetimeMs: 75, displayRating: 600),
    .init(level: 3, skill: 4, depth: 3, movetimeMs: 100, displayRating: 800),
    .init(level: 4, skill: 6, depth: 5, movetimeMs: 150, displayRating: 1000),
    .init(level: 5, skill: 9, depth: 7, movetimeMs: 200, displayRating: 1300),
    .init(level: 6, skill: 12, depth: 9, movetimeMs: 300, displayRating: 1600),
    .init(level: 7, skill: 16, depth: 12, movetimeMs: 500, displayRating: 1900),
    .init(level: 8, skill: 20, depth: 16, movetimeMs: 1000, displayRating: 2400),
  ]

  public static func level(_ n: Int) -> BotLevel { all[max(1, min(n, all.count)) - 1] }
}

/// Engine opponent at a fixed level (Stockfish `Skill Level` + depth cap).
public struct StockfishBot: BotPlayer {
  public let host: EngineHost
  public let level: BotLevel
  let telemetry: Telemetry

  public init(host: EngineHost, level: BotLevel, telemetry: Telemetry) {
    self.host = host
    self.level = level
    self.telemetry = telemetry
  }

  public var name: String { "Stockfish \(level.level)" }
  public var rating: Int { level.displayRating }
  public var kind: String { "stockfish-\(level.level)" }

  public func move(fen: String) async throws -> String {
    try await telemetry.step("bot.move", metadata: ["kind": .string(kind)]) { ctx in
      let result = try await host.search(
        .stockfish, fen: fen, limit: .depth(level.depth), skillLevel: level.skill)
      ctx.annotate("move", .string(result.bestMove))
      return result.bestMove
    }
  }
}
