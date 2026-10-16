import ChessCoachKit
import Foundation
import Observation
import SwiftUI

/// Composition root: the app's long-lived services, created once at launch.
@MainActor
@Observable
final class AppEnvironment {
  let database: AppDatabase
  let gameStore: GameStore
  let analysisStore: AnalysisStore
  let positionCache: PositionCache
  let aiStore: AIStore
  let ai: AnthropicClient
  let aiExplainer: AIExplainer
  let server: ServerLink
  /// Learner summary for the teaching bot (set by TrainingService).
  @ObservationIgnored var learnerBrief: @Sendable () -> String = { "A beginner around 300–500." }
  let telemetry: Telemetry
  let databaseSink: DatabaseSink
  let engineHost: EngineHost?
  let sounds: SoundPlayer
  /// The on-disk store failed to open and we're running in memory (nothing persists).
  let isDegraded: Bool
  /// UI tests / previews run on a throwaway in-memory store.
  let isInMemory: Bool

  init(inMemory: Bool = false) {
    let database: AppDatabase
    var degraded = false
    var openError: String?
    do {
      database = inMemory ? try .inMemory() : try .onDisk()
    } catch {
      // A broken on-disk store must not brick the app; fall back to memory (and say so).
      database = try! .inMemory()
      degraded = true
      openError = String(describing: error)
    }
    isDegraded = degraded
    isInMemory = inMemory
    self.database = database
    gameStore = GameStore(database: database)
    analysisStore = AnalysisStore(database: database)
    positionCache = PositionCache(database: database)
    let aiStore = AIStore(database: database)
    self.aiStore = aiStore
    databaseSink = DatabaseSink(database: database)
    telemetry = Telemetry(sinks: [OSLogSink(), databaseSink])
    let engineTelemetry = Telemetry(sinks: [OSLogSink(), databaseSink])
    engineHost = EngineAssets.bundled().map { EngineHost(assets: $0, telemetry: engineTelemetry) }
    sounds = SoundPlayer()
    let ai = AnthropicClient(keyProvider: { KeyStore.read() }, telemetry: telemetry, ledger: aiStore, monthlyCapUSD: 80)
    self.ai = ai
    aiExplainer = AIExplainer(client: ai, store: aiStore)
    server = ServerLink(telemetry: telemetry)

    telemetry.event("app.launch", metadata: ["engines": .bool(engineHost != nil), "degradedDB": .bool(degraded)])
    if let openError { telemetry.event("db.openFailed", metadata: ["error": .string(openError)]) }
    let sink = databaseSink
    Task.detached(priority: .background) {
      try? sink.prune(olderThan: Date().addingTimeInterval(-30 * 86_400))
    }
  }

  /// Builds the bot for an opponent choice.
  func bot(for opponent: Opponent) -> BotPlayer? {
    guard let engineHost else { return nil }
    switch opponent {
    case .maia(let rating):
      return MaiaBot(host: engineHost, rating: rating, telemetry: telemetry)
    case .stockfish(let level):
      return StockfishBot(host: engineHost, level: .level(level), telemetry: telemetry)
    case .teaching:
      let brief = learnerBrief
      return TeachingBot(host: engineHost, client: ai, telemetry: telemetry, brief: { brief() })
    }
  }

  func makeGame(_ config: PlayConfig, coached: Bool = false) -> GameController? {
    guard let engineHost else { return nil }
    // In timed games the coach bot plays without Claude (an API wait would burn its clock).
    let bot: BotPlayer? =
      config.opponent == .teaching && config.timeControl.isTimed
      ? TeachingBot(host: engineHost, client: nil, telemetry: telemetry, brief: learnerBrief)
      : self.bot(for: config.opponent)
    guard let bot else { return nil }
    return GameController(
      config: config, bot: bot, telemetry: telemetry, store: gameStore, sounds: sounds,
      coach: coached ? StockfishCoach(host: engineHost) : nil)
  }
}

/// User display preferences (board theme, pieces, sound).
enum BoardSettings {
  static let themeKey = "board.theme"
  static let piecesKey = "board.pieces"
  static let soundKey = "board.sound"
  static let coordinatesKey = "board.coordinates"
}
