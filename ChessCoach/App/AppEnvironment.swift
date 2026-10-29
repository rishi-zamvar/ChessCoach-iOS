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
  let ai: LLMClient
  let aiSettings = AISettings()
  let aiExplainer: AIExplainer
  let server: ServerLink
  /// Learner summary for the teaching bot (set by TrainingService).
  @ObservationIgnored var learnerBrief: @Sendable () -> String = { "A beginner around 300–500." }
  let telemetry: Telemetry
  let databaseSink: DatabaseSink
  /// In-app feedback: breadcrumbs, outbox, status (spec W8).
  let feedback: FeedbackCenter
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
    // UI tests start fresh: openings added in an earlier run would leave the Add list.
    if inMemory { UserDefaults.standard.removeObject(forKey: Self.addedOpeningsKey) }
    self.database = database
    gameStore = GameStore(database: database)
    analysisStore = AnalysisStore(database: database)
    positionCache = PositionCache(database: database)
    let aiStore = AIStore(database: database)
    self.aiStore = aiStore
    databaseSink = DatabaseSink(database: database)
    var telemetryRef: Telemetry?
    let feedback = FeedbackCenter(telemetry: { telemetryRef })
    self.feedback = feedback
    var sinks: [TelemetrySink] = [OSLogSink(), databaseSink, feedback.breadcrumbs]
    if let client = AnalyticsSetup.start(inMemory: inMemory) {
      sinks.append(AnalyticsSink(client: client, consent: { AnalyticsSetup.consent }))
    }
    telemetry = Telemetry(sinks: sinks)
    telemetryRef = telemetry
    let engineTelemetry = Telemetry(sinks: [OSLogSink(), databaseSink])
    engineHost = EngineAssets.bundled().map { EngineHost(assets: $0, telemetry: engineTelemetry) }
    sounds = SoundPlayer()
    let ai = LLMClient(config: { AISettings.config() }, telemetry: telemetry, ledger: aiStore, monthlyCapUSD: 80)
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

  /// Puzzle skill ratings (set by TrainingService): the coach's focus falls back to them.
  @ObservationIgnored var puzzleRatings: () -> [String: Double] = { [:] }

  /// Your repertoire style (set by TrainingService): coach games follow its lines.
  @ObservationIgnored var repertoireStyle: () -> String = { "allRounder" }
  /// Openings added from the Openings screen (comma-separated file names).
  static let addedOpeningsKey = "openings.added"

  /// Your slips in coach games (decayed), which pick each game's focus.
  var coachWeakness: WeaknessTally {
    get {
      UserDefaults.standard.data(forKey: "coach.weakness").flatMap { try? JSONDecoder().decode(WeaknessTally.self, from: $0) } ?? WeaknessTally()
    }
    set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "coach.weakness") }
  }

  var coachFocus: CoachFocus { coachWeakness.focus(puzzleRatings: puzzleRatings()) }

  /// Coach bot games get the staged coach: your repertoire in the opening, the AI coach vetting
  /// your middlegame against your goals, mates in the endgame; set-ups for your focus, hold-ups
  /// before mistakes cost you (untimed), and the voice. In timed games the bot plays without AI (an API wait
  /// would burn its clock) and there are no hold-ups.
  func makeGame(_ config: PlayConfig) -> GameController? {
    guard let engineHost else { return nil }
    let coached = config.opponent == .teaching
    let timed = config.timeControl.isTimed
    let focus = coached ? coachFocus : nil
    let bot: BotPlayer? =
      coached
      ? TeachingBot(host: engineHost, client: timed ? nil : ai, telemetry: telemetry, brief: learnerBrief, focus: { focus })
      : self.bot(for: config.opponent)
    guard let bot else { return nil }
    let game = GameController(
      config: config, bot: bot, telemetry: telemetry, store: gameStore, sounds: sounds,
      coach: coached && !timed ? StockfishCoach(host: engineHost) : nil,
      voice: CoachMode.current == .off ? nil : StockfishCoach(host: engineHost),
      focus: focus, writer: coached && !timed ? LLMCoachWriter(client: ai) : nil,
      opening: coached ? OpeningGuide(
        style: repertoireStyle(),
        added: (UserDefaults.standard.string(forKey: Self.addedOpeningsKey) ?? "").split(separator: ",").map(String.init),
        userColor: config.userColor) : nil,
      growth: coachWeakness.summary)
    if coached {
      game.onFinished = { [weak self] slips in
        guard let self else { return }
        self.coachWeakness = self.coachWeakness.adding(slips)
      }
    }
    return game
  }

}

/// User display preferences (board theme, pieces, sound).
enum BoardSettings {
  static let themeKey = "board.theme"
  static let piecesKey = "board.pieces"
  static let soundKey = "board.sound"
  static let coordinatesKey = "board.coordinates"
  static let paceKey = "board.pace"
  static let coachModeKey = "coach.mode"
}

/// The coach in your corner during games.
enum CoachMode: String, CaseIterable, Identifiable {
  case voice, text, off
  var id: String { rawValue }
  var title: String {
    switch self {
    case .voice: "Speaks"
    case .text: "Text only"
    case .off: "Off"
    }
  }
  static var current: CoachMode {
    CoachMode(rawValue: UserDefaults.standard.string(forKey: BoardSettings.coachModeKey) ?? "") ?? .voice
  }
}

/// How the opponent's replies are shown in puzzles and lessons.
enum ReplyPace: String, CaseIterable, Identifiable {
  case instant, normal, step
  var id: String { rawValue }
  var title: String {
    switch self {
    case .instant: "Instant"
    case .normal: "Pause"
    case .step: "Tap to continue"
    }
  }
  /// Pause before the reply; nil waits for a tap.
  var delay: Duration? {
    switch self {
    case .instant: .milliseconds(150)
    case .normal: .milliseconds(900)
    case .step: nil
    }
  }
}
