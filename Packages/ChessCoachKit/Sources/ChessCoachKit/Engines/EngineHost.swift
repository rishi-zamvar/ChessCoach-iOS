import ChessKit
import ChessKitEngine
import Foundation

/// Locations of the engine network files.
public struct EngineAssets: Sendable {
  public var nnueBig: URL
  public var nnueSmall: URL
  public var maiaWeights: [Int: URL]

  public init(nnueBig: URL, nnueSmall: URL, maiaWeights: [Int: URL]) {
    self.nnueBig = nnueBig
    self.nnueSmall = nnueSmall
    self.maiaWeights = maiaWeights
  }

  /// Assets shipped in an app bundle (`ChessCoach/Resources/Engines`).
  public static func bundled(in bundle: Bundle = .main) -> EngineAssets? {
    guard let big = bundle.url(forResource: "nn-1111cefa1111", withExtension: "nnue"),
      let small = bundle.url(forResource: "nn-37f18f62d772", withExtension: "nnue")
    else { return nil }
    var maia: [Int: URL] = [:]
    for rating in stride(from: 1100, through: 1900, by: 100) {
      if let url = bundle.url(forResource: "maia-\(rating).pb", withExtension: "gz") {
        maia[rating] = url
      }
    }
    return EngineAssets(nnueBig: big, nnueSmall: small, maiaWeights: maia)
  }
}

/// Which engine (and network) a search runs on.
public enum EngineKind: Hashable, Sendable {
  case stockfish
  case maia(rating: Int)
}

/// How long a search may run.
public enum SearchLimit: Sendable, Equatable {
  case depth(Int)
  case nodes(Int)
  case movetime(milliseconds: Int)
  /// Stop at `depth` or after `milliseconds`, whichever comes first (fast game review).
  case depthOrTime(depth: Int, milliseconds: Int)
}

/// An engine score from the side-to-move's point of view.
public enum EngineScore: Sendable, Equatable {
  case centipawns(Int)
  /// Mate in N moves; negative when the side to move is getting mated.
  case mate(Int)
}

public struct EngineLine: Sendable, Equatable {
  public var multipv: Int
  public var depth: Int
  public var score: EngineScore
  /// Principal variation in UCI notation.
  public var pv: [String]

  public init(multipv: Int, depth: Int, score: EngineScore, pv: [String]) {
    self.multipv = multipv
    self.depth = depth
    self.score = score
    self.pv = pv
  }
}

public struct SearchResult: Sendable, Equatable {
  public var bestMove: String
  /// Best line first (sorted by multipv index).
  public var lines: [EngineLine]
  /// Lc0 policy priors per UCI move (only for Maia searches), summing to ~1.
  public var policy: [String: Double]
}

public enum EngineError: Error, Equatable {
  case missingWeights(rating: Int)
  case timedOut
  case noBestMove
}

/// Owns the single in-process engine.
///
/// chesskit-engine redirects the process's stdin/stdout through global pipes,
/// so only ONE engine can run at a time. EngineHost serializes every search and
/// switches between Stockfish and Lc0 (Maia) on demand.
public actor EngineHost {
  private let assets: EngineAssets
  private let telemetry: Telemetry
  private var engine: Engine?
  private var running: EngineKind?
  private var currentMultiPV = 0
  private var currentSkill = 20
  private var readerTask: Task<Void, Never>?

  /// Each wait gets a generation number so a stale timeout can't cancel a newer wait.
  private var generation = 0
  private var pendingReady: (gen: Int, cont: CheckedContinuation<Bool, Never>)?
  private var pendingSearch: (gen: Int, cont: CheckedContinuation<String?, Never>)?
  private var lines: [Int: EngineLine] = [:]
  private var policy: [String: Double] = [:]
  /// Squares holding the side-to-move's pieces in the position being searched; an
  /// `info` PV whose first move starts elsewhere is stale output from an earlier search.
  private var validFromSquares: Set<String> = []

  /// FIFO lock: an actor only serializes between awaits, but a search spans many awaits,
  /// so searches queue here and run strictly one at a time.
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init(assets: EngineAssets, telemetry: Telemetry = .logOnly) {
    self.assets = assets
    self.telemetry = telemetry
  }

  /// Runs one search and returns the best move plus lines.
  ///
  /// A search that times out restarts the engine and is retried once.
  public func search(
    _ kind: EngineKind,
    fen: String,
    limit: SearchLimit,
    multipv: Int = 1,
    skillLevel: Int? = nil
  ) async throws -> SearchResult {
    await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try await telemetry.step(
      "engine.search",
      metadata: ["kind": .string(Self.label(kind)), "limit": .string(Self.label(limit)), "multipv": .int(multipv)]
    ) { ctx in
      do {
        return try await searchOnce(kind, fen: fen, limit: limit, multipv: multipv, skillLevel: skillLevel, ctx: ctx)
      } catch EngineError.timedOut {
        ctx.annotate("retried", .bool(true))
        await stopEngine()
        return try await searchOnce(kind, fen: fen, limit: limit, multipv: multipv, skillLevel: skillLevel, ctx: ctx)
      }
    }
  }

  static func sideToMoveSquares(fen: String) -> Set<String> {
    guard let position = Position(fen: fen) else { return [] }
    let side = position.sideToMove
    let squares: [String] = position.pieces.filter { $0.color == side }.map { $0.square.notation }
    return Set(squares)
  }

  private func acquire() async {
    if busy {
      await withCheckedContinuation { waiters.append($0) }
    } else {
      busy = true
    }
  }

  private func release() {
    if waiters.isEmpty {
      busy = false
    } else {
      waiters.removeFirst().resume()  // ownership passes straight to the next waiter
    }
  }

  private func cancelSearch(_ gen: Int) async {
    guard let pending = pendingSearch, pending.gen == gen else { return }
    // The engine answers `stop` with a bestmove, which resumes the waiting search.
    await engine?.send(command: .stop)
  }

  private func searchOnce(
    _ kind: EngineKind, fen: String, limit: SearchLimit, multipv: Int, skillLevel: Int?, ctx: StepContext
  ) async throws -> SearchResult {
    try await prepare(kind, multipv: multipv, skillLevel: skillLevel)
    guard let engine else { throw EngineError.noBestMove }

    lines = [:]
    policy = [:]
    validFromSquares = Self.sideToMoveSquares(fen: fen)
    await engine.send(command: .position(.fen(fen)))
    let go: EngineCommand =
      switch limit {
      case .depth(let d): .go(depth: d)
      case .nodes(let n): .go(nodes: n)
      case .movetime(let ms): .go(movetime: ms)
      case .depthOrTime(let d, let ms): .go(depth: d, movetime: ms)
      }
    generation += 1
    let gen = generation
    let best = await withTaskCancellationHandler {
      await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
        pendingSearch = (gen, cont)
        Task { await engine.send(command: go) }
        Task { [timeout = Self.timeout(for: limit)] in
          try? await Task.sleep(for: timeout)
          await self.expireSearch(gen)
        }
      }
    } onCancel: {
      Task { await self.cancelSearch(gen) }
    }
    try Task.checkCancellation()
    guard let best else {
      await engine.send(command: .stop)
      throw EngineError.timedOut
    }
    guard best != "(none)", !best.isEmpty else { throw EngineError.noBestMove }
    // chesskit-engine delivers each output line in its own Task, so the last `info`
    // lines can land just after `bestmove`. Let them drain.
    try? await Task.sleep(for: .milliseconds(15))
    let sorted = lines.values.sorted { $0.multipv < $1.multipv }
    let total = policy.values.reduce(0, +)
    let normalized = total > 0 ? policy.mapValues { $0 / total } : [:]
    ctx.annotate("best", .string(best))
    ctx.annotate("depth", .int(sorted.first?.depth ?? 0))
    return SearchResult(bestMove: best, lines: sorted, policy: normalized)
  }

  /// Stops whichever engine is running (waits for any search in progress).
  public func shutdown() async {
    await acquire()
    defer { release() }
    await stopEngine()
  }

  private func stopEngine() async {
    guard let engine else { return }
    telemetry.event("engine.shutdown", metadata: ["type": .string(engine.type.name)])
    // Don't send an extra `quit` first: an engine that fully exits can't be restarted
    // in-process (the next boot's handshake hangs ~20 s). Measured 2026-10-16.
    await engine.stop()
    // chesskit-engine closes the pipes right after `quit`; give the C++ engine thread
    // time to unwind before another engine (or process exit) reuses stdin/stdout.
    try? await Task.sleep(for: .milliseconds(300))
    readerTask?.cancel()
    readerTask = nil
    self.engine = nil
    running = nil
    pendingReady?.cont.resume(returning: false)
    pendingReady = nil
    pendingSearch?.cont.resume(returning: nil)
    pendingSearch = nil
  }

  // MARK: - Lifecycle

  private func prepare(_ kind: EngineKind, multipv: Int, skillLevel: Int?) async throws {
    if case .maia(let rating) = kind, assets.maiaWeights[rating] == nil {
      throw EngineError.missingWeights(rating: rating)
    }
    let type: EngineType = kind == .stockfish ? .stockfish : .lc0
    if engine?.type != type {
      await stopEngine()
      try await boot(type)
    }
    if running != kind {
      switch kind {
      case .stockfish:
        await engine?.send(command: .setoption(id: "EvalFile", value: assets.nnueBig.path))
        await engine?.send(command: .setoption(id: "EvalFileSmall", value: assets.nnueSmall.path))
      case .maia(let rating):
        await engine?.send(command: .setoption(id: "WeightsFile", value: assets.maiaWeights[rating]!.path))
        await engine?.send(command: .setoption(id: "VerboseMoveStats", value: "true"))
      }
      running = kind
      currentMultiPV = 0
      currentSkill = 20
    }
    // Stockfish strength: nil means full strength (analysis).
    if kind == .stockfish, (skillLevel ?? 20) != currentSkill {
      currentSkill = skillLevel ?? 20
      await engine?.send(command: .setoption(id: "Skill Level", value: "\(currentSkill)"))
    }
    if currentMultiPV != multipv {
      await engine?.send(command: .setoption(id: "MultiPV", value: "\(multipv)"))
      currentMultiPV = multipv
    }
    try await waitReady()
  }

  private func boot(_ type: EngineType) async throws {
    try await telemetry.step("engine.boot", metadata: ["type": .string(type.name)]) { _ in
      let engine = Engine(type: type)
      await engine.start(coreCount: max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
      // The library sets isRunning after its uci/isready handshake completes.
      var waited = 0
      while await !engine.isRunning {
        try? await Task.sleep(for: .milliseconds(20))
        waited += 20
        if waited > 15_000 {
          // Never leave a half-started engine installed.
          await engine.send(command: .quit)
          await engine.stop()
          throw EngineError.timedOut
        }
      }
      guard let stream = await engine.responseStream else {
        await engine.stop()
        throw EngineError.timedOut
      }
      self.engine = engine
      readerTask = Task { [weak self] in
        for await response in stream {
          await self?.handle(response)
        }
      }
    }
  }

  private func waitReady() async throws {
    guard let engine else { return }
    generation += 1
    let gen = generation
    let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
      pendingReady = (gen, cont)
      Task { await engine.send(command: .isready) }
      Task {
        try? await Task.sleep(for: .seconds(20))
        await self.expireReady(gen)
      }
    }
    if !ok { throw EngineError.timedOut }
  }

  private func expireReady(_ gen: Int) {
    guard let pending = pendingReady, pending.gen == gen else { return }
    pendingReady = nil
    pending.cont.resume(returning: false)
  }

  private func expireSearch(_ gen: Int) {
    guard let pending = pendingSearch, pending.gen == gen else { return }
    pendingSearch = nil
    pending.cont.resume(returning: nil)
  }

  static func timeout(for limit: SearchLimit) -> Duration {
    switch limit {
    case .depth(let d): .seconds(max(20, d * 4))
    case .nodes: .seconds(20)
    case .movetime(let ms), .depthOrTime(_, let ms): .milliseconds(ms + 15_000)
    }
  }

  static func label(_ kind: EngineKind) -> String {
    switch kind {
    case .stockfish: "stockfish"
    case .maia(let rating): "maia-\(rating)"
    }
  }

  static func label(_ limit: SearchLimit) -> String {
    switch limit {
    case .depth(let d): "depth \(d)"
    case .nodes(let n): "nodes \(n)"
    case .movetime(let ms): "movetime \(ms)"
    case .depthOrTime(let d, let ms): "depth \(d) / \(ms)ms"
    }
  }

  private func handle(_ response: EngineResponse) {
    switch response {
    case .readyok:
      pendingReady?.cont.resume(returning: true)
      pendingReady = nil
    case .bestmove(let move, _):
      pendingSearch?.cont.resume(returning: move)
      pendingSearch = nil
    case .info(let info):
      if let text = info.string, let (move, prior) = Self.parsePolicy(text) {
        policy[move] = prior
      }
      guard let pv = info.pv, let first = pv.first, let score = info.score else { return }
      // Drop stale lines from a previous search (wrong position).
      guard validFromSquares.contains(String(first.prefix(2))) else { return }
      let engineScore: EngineScore
      if let mate = score.mate {
        engineScore = .mate(mate)
      } else if let cp = score.cp {
        engineScore = .centipawns(Int(cp))
      } else {
        return
      }
      let index = info.multipv ?? 1
      let depth = info.depth ?? 0
      // Output lines can arrive out of order; never let a shallower line overwrite a deeper one.
      if let existing = lines[index], existing.depth > depth { return }
      lines[index] = EngineLine(multipv: index, depth: depth, score: engineScore, pv: pv)
    default:
      break
    }
  }

  /// Parses an Lc0 `VerboseMoveStats` line, e.g.
  /// `e2e4  (322 ) N:       0 (+ 0) (P: 12.34%) (WL: ...` → ("e2e4", 0.1234).
  static func parsePolicy(_ text: String) -> (String, Double)? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let move = trimmed.split(separator: " ").first.map(String.init),
      move.count >= 4, move.count <= 5, move != "node",
      let pRange = trimmed.range(of: "(P:")
    else { return nil }
    let rest = trimmed[pRange.upperBound...].trimmingCharacters(in: .whitespaces)
    guard let pct = rest.split(separator: "%").first.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) })
    else { return nil }
    return (move, pct / 100)
  }
}
