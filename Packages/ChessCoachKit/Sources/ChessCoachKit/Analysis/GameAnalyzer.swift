import ChessKit
import Foundation

/// Why a move went wrong (feeds training and Recurring Mistakes).
public enum MistakeType: String, Codable, CaseIterable, Sendable {
  case missedTactic, allowedTactic, hungMaterial, endgameError, failedConversion, positional

  public var displayName: String {
    switch self {
    case .missedTactic: "Missed tactic"
    case .allowedTactic: "Allowed a tactic"
    case .hungMaterial: "Hung material"
    case .endgameError: "Endgame error"
    case .failedConversion: "Let a win slip"
    case .positional: "Positional slip"
    }
  }
}

public struct MoveAnalysis: Codable, Equatable, Sendable, Identifiable {
  public var id: Int { ply }
  /// 1-based ply of this move.
  public var ply: Int
  public var san: String
  public var uci: String
  public var color: String
  public var fenBefore: String
  /// The mover's expected points (0…1) before (best play) and after the move.
  public var bestEP: Double
  public var playedEP: Double
  public var bestUCI: String?
  /// Engine moves within 2% of the best (also accepted in Retry).
  public var goodMoves: [String] = []
  public var bestLine: [String]
  public var label: MoveClass
  public var accuracy: Double
  public var facts: FactSheet?
  public var explanation: String
  public var mistakeType: MistakeType?
  public var timeTrouble: Bool
  public var clock: TimeInterval?

  public var loss: Double { max(0, bestEP - playedEP) }
  public var isWhite: Bool { color == "white" }
}

public struct GameAnalysis: Codable, Equatable, Sendable {
  public var gameID: String
  public var engine: String
  public var depth: Int
  public var userColor: String
  public var startFEN: String
  public var moves: [MoveAnalysis]
  /// White's win% (0…100) at the start and after every ply (eval graph).
  public var whiteWin: [Double]
  public var accuracyWhite: Double?
  public var accuracyBlack: Double?
  public var openingName: String?
  public var createdAt: Date

  public var userAccuracy: Double? { userColor == "white" ? accuracyWhite : accuracyBlack }

  /// Plies worth stopping on in a review (user's critical moves + opponent blunders).
  public var keyMoments: [Int] {
    moves.filter { m in
      m.label.isCritical && (m.color == userColor || m.label == .blunder)
    }.map(\.ply)
  }

  public func counts(for color: String) -> [MoveClass: Int] {
    moves.filter { $0.color == color }.reduce(into: [:]) { $0[$1.label, default: 0] += 1 }
  }

  /// Accuracy per phase for a side (mean of move accuracies).
  public func phaseAccuracy(_ phase: GamePhaseKind, color: String) -> Double? {
    let xs = moves.filter { $0.color == color && $0.facts?.phase == phase }.map(\.accuracy)
    return xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
  }
}

/// Runs the engine over a game and builds the full review.
public struct GameAnalyzer: Sendable {
  public let host: EngineHost
  public let telemetry: Telemetry
  public let depth: Int
  /// Rating whose Maia model judges "would a human find this" for Brilliant.
  public let maiaRating: Int?
  /// Per-position time cap (ms); nil = depth only.
  public let msPerPosition: Int?
  let cache: PositionCache?

  public init(
    host: EngineHost, telemetry: Telemetry, depth: Int = 12, maiaRating: Int? = 1100, cache: PositionCache? = nil,
    msPerPosition: Int? = 250
  ) {
    self.host = host
    self.telemetry = telemetry
    self.depth = depth
    self.maiaRating = maiaRating
    self.cache = cache
    self.msPerPosition = msPerPosition
  }

  public func analyze(gameID: String, pgn: String, userColor: String, timeControl: String) async throws -> GameAnalysis {
    guard let session = GameSession(pgn: pgn) else { throw AnalysisError.unreadablePGN }
    return try await telemetry.step(
      "analysis.game", metadata: ["game": .string(gameID), "plies": .int(session.history.count), "depth": .int(depth)]
    ) { ctx in
      // 1. Evaluate every position (start + after each ply).
      let fens = (0...session.history.count).map { session.fen(atPly: $0) }
      var evals: [PositionEval] = []
      var coolingLeft = 30  // one 60 s cooling budget per game, not per position
      for (i, fen) in fens.enumerated() {
        try Task.checkCancellation()
        // Spec §4: back off when the phone is hot instead of cooking it.
        while coolingLeft > 0, ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
          if coolingLeft == 30 { telemetry.event("analysis.thermalPause", parent: ctx) }
          try await Task.sleep(for: .seconds(2))
          coolingLeft -= 1
        }
        evals.append(try await evaluate(fen: fen, parent: ctx))
        ctx.progress(done: i + 1, total: fens.count)
      }

      // 2. Judge each move.
      let base = PGNClocks.baseSeconds(timeControl: timeControl)
      var moves: [MoveAnalysis] = []
      var previousLoss: Double?
      for (index, played) in session.history.enumerated() {
        let before = evals[index]
        let after = evals[index + 1]
        let mover = played.color
        let bestEP = before.sideToMoveWin / 100
        let playedEP = 1 - after.sideToMoveWin / 100
        let bestUCI = before.lines.first?.pv.first
        let playedIsBest = bestUCI == played.uci
        let secondEP = before.lines.count > 1 ? WinChance.winPercent(before.lines[1].score) / 100 : nil
        let sacrifice = Self.isSacrifice(fen: fens[index], uci: played.uci)

        var plyEval = PlyEval(
          legalMoveCount: before.legalMoves, isBook: false, bestEP: bestEP, secondBestEP: secondEP,
          playedEP: playedEP, playedIsBest: playedIsBest, isSacrifice: sacrifice, maiaProbability: nil,
          opponentPreviousLoss: previousLoss)
        plyEval.isBook = OpeningBook.shared.isBook(fenAfter: fens[index + 1])
        if sacrifice, plyEval.loss <= 0.02, playedEP > 0.4, let rating = maiaRating {
          plyEval.maiaProbability = try? await maiaProbability(fen: fens[index], uci: played.uci, rating: rating)
        }
        let sheet = FactExtractor.sheet(
          fen: fens[index], played: played.uci, bestLine: before.lines.first?.pv ?? [],
          punishLine: after.lines.first?.pv ?? [], ply: index)
        plyEval.bestIsTactical = !Self.tactical.isDisjoint(with: sheet?.best?.motifs ?? [])
        plyEval.allowsTactic = !Self.tactical.isDisjoint(with: sheet?.punish?.motifs ?? []) || !(sheet?.hangingAfter.isEmpty ?? true)
        let label = MoveClassifier.classify(plyEval)
        previousLoss = plyEval.loss
        let isUser = (mover == .white ? "white" : "black") == userColor
        let explanation = sheet.map { Explainer.explain($0, as: label, isUser: isUser) } ?? ""
        let timeTrouble = base.map { b in (played.clockAfter ?? b) < b * 0.1 } ?? false

        moves.append(
          MoveAnalysis(
            ply: index + 1, san: played.san, uci: played.uci, color: mover == .white ? "white" : "black",
            fenBefore: fens[index], bestEP: bestEP, playedEP: playedEP, bestUCI: bestUCI,
            goodMoves: before.lines.filter { bestEP - WinChance.winPercent($0.score) / 100 <= 0.02 }.compactMap(\.pv.first),
            bestLine: sheet?.bestLineSAN ?? [], label: label,
            accuracy: WinChance.moveAccuracy(winBefore: bestEP * 100, winAfter: playedEP * 100),
            facts: sheet, explanation: explanation,
            mistakeType: label.isError ? Self.mistakeType(sheet: sheet, bestEP: bestEP, playedEP: playedEP) : nil,
            timeTrouble: timeTrouble, clock: played.clockAfter))
      }

      // 3. Graph + accuracy.
      let whiteWin = zip(fens, evals).map { fen, eval in
        fen.split(separator: " ")[1] == "w" ? eval.sideToMoveWin : 100 - eval.sideToMoveWin
      }
      let whiteFirst = fens[0].split(separator: " ")[1] == "w"
      let accuracy = WinChance.gameAccuracy(whiteWinPercents: whiteWin, whiteMovesFirst: whiteFirst)
      ctx.annotate("errors", .int(moves.filter { $0.color == userColor && $0.label.isError }.count))
      return GameAnalysis(
        gameID: gameID, engine: "stockfish-17", depth: depth, userColor: userColor, startFEN: fens[0],
        moves: moves, whiteWin: whiteWin, accuracyWhite: accuracy.white, accuracyBlack: accuracy.black,
        openingName: OpeningBook.shared.name(of: session)?.name, createdAt: Date())
    }
  }

  // MARK: - Engine

  struct PositionEval: Sendable {
    var lines: [EngineLine]
    /// Win% for the side to move (0…100).
    var sideToMoveWin: Double
    var legalMoves: Int
  }

  func evaluate(fen: String, parent: StepContext) async throws -> PositionEval {
    let legal = Self.legalMoveCount(fen: fen)
    if legal == 0 {
      // Game over: checkmated side to move scores 0, stalemate 50.
      // (chesskit's Board(position:) doesn't flag mate without a last move, so check the king directly.)
      let position = Position(fen: fen) ?? .standard
      let map = BoardMap(position)
      let side = position.sideToMove
      let inCheck = map.king(of: side).map { !map.attackers(of: $0, by: side.opposite).isEmpty } ?? false
      return PositionEval(lines: [], sideToMoveWin: inCheck ? 0 : 50, legalMoves: 0)
    }
    let key = FENTools.key(fen)
    // Time-capped searches can stop short of `depth`; accept cached lines a little shallower.
    if let cached = cache?.lookup(fenKey: key, minDepth: msPerPosition == nil ? depth : max(1, depth - 4)) {
      return PositionEval(lines: cached, sideToMoveWin: WinChance.winPercent(cached[0].score), legalMoves: legal)
    }
    let limit: SearchLimit = msPerPosition.map { .depthOrTime(depth: depth, milliseconds: $0) } ?? .depth(depth)
    // MultiPV 2 is enough for "Great" (best vs second-best); 3 costs ~50% more.
    let result = try await host.search(.stockfish, fen: fen, limit: limit, multipv: min(2, legal))
    guard let first = result.lines.first else { throw EngineError.noBestMove }
    // Record the depth actually reached (time-capped searches can stop short).
    cache?.store(fenKey: key, depth: result.lines.map(\.depth).max() ?? 0, lines: result.lines)
    return PositionEval(lines: result.lines, sideToMoveWin: WinChance.winPercent(first.score), legalMoves: legal)
  }

  func maiaProbability(fen: String, uci: String, rating: Int) async throws -> Double {
    let result = try await host.search(.maia(rating: rating), fen: fen, limit: .nodes(1))
    return result.policy[uci] ?? 0
  }

  // MARK: - Helpers

  static func legalMoveCount(fen: String) -> Int {
    let session = GameSession(startFEN: fen)
    return session.position.pieces.filter { $0.color == session.sideToMove }
      .reduce(0) { $0 + session.legalTargets(from: $1.square).count }
  }

  /// The move puts the moved piece where the opponent wins ≥ 2 by exchange.
  static func isSacrifice(fen: String, uci: String) -> Bool {
    var session = GameSession(startFEN: fen)
    guard case .applied(let played) = session.apply(uci: uci) else { return false }
    let map = BoardMap(session.position)
    let net = StaticExchange.evaluate(map, square: played.move.end, by: played.color.opposite)
    var gained = 0
    if case .capture(let captured) = played.move.result { gained = PieceValue.of(captured.kind) }
    return net - gained >= 2
  }

  static let tactical: Set<Motif> = [.mate, .fork, .pin, .skewer, .discoveredAttack, .winsMaterial, .mateThreat]

  static func mistakeType(sheet: FactSheet?, bestEP: Double, playedEP: Double) -> MistakeType {
    guard let sheet else { return .positional }
    if let punish = sheet.punish, !tactical.isDisjoint(with: punish.motifs) { return .allowedTactic }
    if !sheet.hangingAfter.isEmpty { return .hungMaterial }
    if let best = sheet.best, !tactical.isDisjoint(with: best.motifs) { return .missedTactic }
    if sheet.phase == .endgame { return .endgameError }
    if bestEP >= 0.7 && playedEP < 0.6 { return .failedConversion }
    return .positional
  }
}

public enum AnalysisError: Error, Equatable {
  case unreadablePGN
}
