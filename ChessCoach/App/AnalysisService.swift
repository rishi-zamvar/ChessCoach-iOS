import ChessCoachKit
import Foundation
import Observation

/// Imports chess.com games and runs game analysis, publishing progress for the UI.
@MainActor
@Observable
final class AnalysisService {
  struct Progress: Equatable {
    var gameID: String
    var done: Int
    var total: Int
    /// Estimated seconds left, from past runs' median duration.
    var etaSeconds: Double?
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
  }

  enum ImportState: Equatable {
    case idle
    case running
    case finished(newGames: Int)
    case failed(String)
  }

  private(set) var progress: Progress?
  private(set) var importState: ImportState = .idle
  private(set) var analyzedIDs: Set<String> = []
  private(set) var revision = 0
  /// When chess.com was last checked successfully (survives relaunches).
  private(set) var lastImportAt: Date? = UserDefaults.standard.object(forKey: AnalysisService.lastImportKey) as? Date
  /// Called after an import that brought in games (e.g. to re-anchor the rating).
  @ObservationIgnored var onImported: () -> Void = {}
  static let lastImportKey = "chesscom.lastImport"

  @ObservationIgnored private let env: AppEnvironment
  @ObservationIgnored private var running: [String: Task<GameAnalysis, Error>] = [:]
  @ObservationIgnored private var progressWatcher: Task<Void, Never>?
  @ObservationIgnored private var backgroundTask: Task<Void, Never>?
  @ObservationIgnored private var backgroundGameID: String?
  @ObservationIgnored private var backgroundToken: UUID?
  @ObservationIgnored private var foregroundUsers = 0
  /// Games analyzed in the background this session (for the UI).
  private(set) var backgroundAnalyzed = 0

  static let usernameKey = "chesscom.username"
  static let etagsKey = "chesscom.etags"

  var username: String {
    get { UserDefaults.standard.string(forKey: Self.usernameKey) ?? "Zammy009" }
    set { UserDefaults.standard.set(newValue, forKey: Self.usernameKey) }
  }

  init(env: AppEnvironment) {
    self.env = env
    analyzedIDs = (try? env.analysisStore.analyzedGameIDs()) ?? []
    watchProgress()
  }

  // MARK: - Import

  func importFromChessCom() async {
    guard importState != .running else { return }
    importState = .running
    let client = ChessComClient(telemetry: env.telemetry)
    let importer = ChessComImporter(client: client, telemetry: env.telemetry)
    do {
      let known = try env.gameStore.ids(source: .chesscom)
      // ETags say "you already have this month" — only true if the games are actually stored.
      let etags = known.isEmpty ? [:] : (UserDefaults.standard.dictionary(forKey: Self.etagsKey) as? [String: String]) ?? [:]
      let batch = try await importer.importGames(username: username, knownURLs: known, monthETags: etags)
      let inserted = try env.gameStore.insertNew(batch.games.map(GameRecord.init(imported:)))
      // Don't remember months as fetched if this session's games won't persist.
      if !env.isDegraded, !env.isInMemory {
        UserDefaults.standard.set(etags.merging(batch.etags) { _, new in new }, forKey: Self.etagsKey)
      }
      importState = .finished(newGames: inserted)
      lastImportAt = Date()
      UserDefaults.standard.set(lastImportAt, forKey: Self.lastImportKey)
      revision += 1
      onImported()
      startBackgroundAnalysis()
    } catch ChessComError.userNotFound {
      importState = .failed("chess.com user “\(username)” not found.")
    } catch ChessComError.rateLimited {
      importState = .failed("chess.com is rate-limiting us. Try again in a minute.")
    } catch {
      importState = .failed("Import failed. Check your connection and try again.")
    }
  }

  /// Event-driven refresh: on launch and whenever the app comes back, if the last
  /// check is older than `interval` (chess.com has no push, so this is the cheap trigger).
  func importIfStale(interval: TimeInterval = 600) async {
    guard !env.isInMemory else { return }
    if let last = lastImportAt, Date().timeIntervalSince(last) < interval { return }
    await importFromChessCom()
  }

  // MARK: - Analysis

  func isAnalyzed(_ gameID: String) -> Bool { analyzedIDs.contains(gameID) }

  func cachedAnalysis(_ gameID: String) -> GameAnalysis? {
    try? env.analysisStore.analysis(gameID: gameID)
  }

  /// Returns the stored analysis, or runs one (shared if already running).
  func analysis(for game: GameRecord) async throws -> GameAnalysis {
    if let cached = cachedAnalysis(game.id) { return cached }
    if let task = running[game.id] { return try await task.value }
    guard let host = env.engineHost else { throw AnalysisError.unreadablePGN }
    let analyzer = GameAnalyzer(
      host: host, telemetry: env.telemetry, maiaRating: 1100, cache: env.positionCache)
    let store = env.analysisStore
    let task = Task {
      let result = try await analyzer.analyze(
        gameID: game.id, pgn: game.pgn, userColor: game.userColor, timeControl: game.timeControl)
      try store.save(result, endedAt: game.endedAt)
      return result
    }
    running[game.id] = task
    defer {
      // Only clear our own entry: a cancelled background run may unwind after the
      // user's review registered a fresh task for the same game.
      if running[game.id] == task {
        running[game.id] = nil
        if progress?.gameID == game.id { progress = nil }
      }
    }
    let result = try await task.value
    analyzedIDs.insert(game.id)
    revision += 1
    return result
  }

  /// Re-runs a review with the home PC's deep Stockfish lines (depth 22). The PC's lines
  /// go into the position cache, so the re-analysis reads them instead of the phone engine.
  func deepAnalyze(_ game: GameRecord) async throws -> GameAnalysis {
    guard let host = env.engineHost else { throw AnalysisError.unreadablePGN }
    progress = Progress(gameID: game.id, done: 0, total: 1, etaSeconds: nil)
    defer { progress = nil }
    let positions = try await env.server.deepAnalysis(gameID: game.id, pgn: game.pgn, userColor: game.userColor) { [weak self] done, total in
      Task { @MainActor in self?.progress = Progress(gameID: game.id, done: done, total: total, etaSeconds: nil) }
    }
    for p in positions {
      env.positionCache.store(fenKey: FENTools.key(p.fen), depth: p.lines.map(\.depth).max() ?? 22, lines: p.lines)
    }
    env.telemetry.event("analysis.deep", metadata: ["game": .string(game.id), "positions": .int(positions.count)])
    let analyzer = GameAnalyzer(host: host, telemetry: env.telemetry, maiaRating: 1100, cache: env.positionCache)
    var result = try await analyzer.analyze(gameID: game.id, pgn: game.pgn, userColor: game.userColor, timeControl: game.timeControl)
    result.engine = "stockfish-pc (depth \(positions.compactMap { $0.lines.first?.depth }.max() ?? 22))"
    try env.analysisStore.save(result, endedAt: game.endedAt)
    revision += 1
    return result
  }

  // MARK: - Background analysis

  /// Analyzes the most recent unanalyzed games (up to `limit`) one at a time so the
  /// daily plan learns from them without the user opening each review.
  func startBackgroundAnalysis(limit: Int = 10) {
    guard backgroundTask == nil, foregroundUsers == 0, env.engineHost != nil else { return }
    let token = UUID()
    backgroundToken = token
    backgroundTask = Task { [weak self] in
      defer {
        // A cancelled run can finish after a newer one started; don't clear the newer one.
        if self?.backgroundToken == token {
          self?.backgroundTask = nil
          self?.backgroundGameID = nil
          self?.backgroundToken = nil
        }
      }
      guard let self else { return }
      let games = ((try? self.env.gameStore.recent(limit: 40)) ?? []).filter { !self.isAnalyzed($0.id) }.prefix(limit)
      for game in games {
        if Task.isCancelled || self.foregroundUsers > 0 { return }
        self.backgroundGameID = game.id
        if (try? await self.analysis(for: game)) != nil { self.backgroundAnalyzed += 1 }
      }
      self.env.telemetry.event("analysis.background", metadata: ["analyzed": .int(self.backgroundAnalyzed)])
    }
  }

  /// Something interactive needs the engine (a game, a review, Play Coach): stop background work.
  func beginForegroundEngineUse() {
    foregroundUsers += 1
    backgroundTask?.cancel()
    backgroundTask = nil
    backgroundToken = nil
    if let id = backgroundGameID {
      running[id]?.cancel()
      running[id] = nil
      backgroundGameID = nil
    }
  }

  func endForegroundEngineUse() {
    foregroundUsers = max(0, foregroundUsers - 1)
    if foregroundUsers == 0 {
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(5))
        self?.startBackgroundAnalysis()
      }
    }
  }

  func recurringPatterns() -> [MistakePattern] {
    (try? env.analysisStore.recurringPatterns()) ?? []
  }

  /// Feeds `progress` from the telemetry stream (analysis.game progress events).
  private func watchProgress() {
    let stream = env.telemetry.events()
    let sink = env.databaseSink
    progressWatcher = Task { [weak self] in
      var currentID: UUID?
      for await event in stream where event.step == "analysis.game" {
        guard let self else { return }
        switch event.phase {
        case .start:
          // Each run's start names its game; later progress events share its step id.
          currentID = event.id
          guard case .string(let gameID) = event.metadata["game"] else { continue }
          let plies: Int = if case .int(let n) = event.metadata["plies"] { n } else { 1 }
          self.progress = Progress(gameID: gameID, done: 0, total: plies + 1, etaSeconds: nil)
          Task.detached(priority: .utility) {
            let eta = try? sink.medianDuration(step: "analysis.game")
            await MainActor.run { if self.progress?.gameID == gameID { self.progress?.etaSeconds = eta.map { $0 / 1000 } } }
          }
        case .progress where event.id == currentID:
          if let done = event.done, let total = event.total {
            self.progress?.done = done
            self.progress?.total = total
          }
        case .finish, .fail:
          if event.id == currentID { self.progress = nil }
        default:
          break
        }
      }
    }
  }
}
