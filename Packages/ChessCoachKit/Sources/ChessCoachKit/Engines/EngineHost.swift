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
  private var engine: Engine?
  private var running: EngineKind?
  private var currentMultiPV = 0
  private var currentSkill = 20
  private var readerTask: Task<Void, Never>?

  private var pendingReady: CheckedContinuation<Void, Never>?
  private var pendingSearch: CheckedContinuation<String, Never>?
  private var lines: [Int: EngineLine] = [:]
  private var policy: [String: Double] = [:]

  public init(assets: EngineAssets) {
    self.assets = assets
  }

  /// Runs one search and returns the best move plus lines.
  public func search(
    _ kind: EngineKind,
    fen: String,
    limit: SearchLimit,
    multipv: Int = 1,
    skillLevel: Int? = nil
  ) async throws -> SearchResult {
    try await prepare(kind, multipv: multipv, skillLevel: skillLevel)
    guard let engine else { throw EngineError.noBestMove }

    lines = [:]
    policy = [:]
    await engine.send(command: .position(.fen(fen)))
    let go: EngineCommand =
      switch limit {
      case .depth(let d): .go(depth: d)
      case .nodes(let n): .go(nodes: n)
      case .movetime(let ms): .go(movetime: ms)
      }
    let best = await withCheckedContinuation { cont in
      pendingSearch = cont
      Task { await engine.send(command: go) }
    }
    guard best != "(none)", !best.isEmpty else { throw EngineError.noBestMove }
    let sorted = lines.values.sorted { $0.multipv < $1.multipv }
    let total = policy.values.reduce(0, +)
    let normalized = total > 0 ? policy.mapValues { $0 / total } : [:]
    return SearchResult(bestMove: best, lines: sorted, policy: normalized)
  }

  /// Stops whichever engine is running.
  public func shutdown() async {
    guard let engine else { return }
    await engine.stop()
    // chesskit-engine closes the pipes right after `quit`; give the C++ engine thread
    // time to unwind before another engine (or process exit) reuses stdin/stdout.
    try? await Task.sleep(for: .milliseconds(300))
    readerTask?.cancel()
    readerTask = nil
    self.engine = nil
    running = nil
  }

  // MARK: - Lifecycle

  private func prepare(_ kind: EngineKind, multipv: Int, skillLevel: Int?) async throws {
    if case .maia(let rating) = kind, assets.maiaWeights[rating] == nil {
      throw EngineError.missingWeights(rating: rating)
    }
    let type: EngineType = kind == .stockfish ? .stockfish : .lc0
    if engine?.type != type {
      await shutdown()
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
    await waitReady()
  }

  private func boot(_ type: EngineType) async throws {
    let engine = Engine(type: type)
    self.engine = engine
    await engine.start(coreCount: max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
    // The library sets isRunning after its uci/isready handshake completes.
    var waited = 0
    while await !engine.isRunning {
      try await Task.sleep(for: .milliseconds(20))
      waited += 20
      if waited > 15_000 { throw EngineError.timedOut }
    }
    guard let stream = await engine.responseStream else { throw EngineError.timedOut }
    readerTask = Task { [weak self] in
      for await response in stream {
        await self?.handle(response)
      }
    }
  }

  private func waitReady() async {
    guard let engine else { return }
    await withCheckedContinuation { cont in
      pendingReady = cont
      Task { await engine.send(command: .isready) }
    }
  }

  private func handle(_ response: EngineResponse) {
    switch response {
    case .readyok:
      pendingReady?.resume()
      pendingReady = nil
    case .bestmove(let move, _):
      pendingSearch?.resume(returning: move)
      pendingSearch = nil
    case .info(let info):
      if let text = info.string, let (move, prior) = Self.parsePolicy(text) {
        policy[move] = prior
      }
      guard let pv = info.pv, !pv.isEmpty, let score = info.score else { return }
      let engineScore: EngineScore
      if let mate = score.mate {
        engineScore = .mate(mate)
      } else if let cp = score.cp {
        engineScore = .centipawns(Int(cp))
      } else {
        return
      }
      let index = info.multipv ?? 1
      lines[index] = EngineLine(multipv: index, depth: info.depth ?? 0, score: engineScore, pv: pv)
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
