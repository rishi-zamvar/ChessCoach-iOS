import ChessKit
import Foundation
import Observation

public enum Opponent: Hashable, Sendable {
  case maia(rating: Int)
  case stockfish(level: Int)
}

public enum ColorChoice: String, CaseIterable, Sendable {
  case white, black, random

  public func resolve(random: RandomSource = SystemRandom()) -> Piece.Color {
    switch self {
    case .white: .white
    case .black: .black
    case .random: random.next() < 0.5 ? .white : .black
    }
  }
}

public struct PlayConfig: Hashable, Sendable {
  public var opponent: Opponent
  public var userColor: Piece.Color
  public var timeControl: TimeControl

  public init(opponent: Opponent, userColor: Piece.Color, timeControl: TimeControl) {
    self.opponent = opponent
    self.userColor = userColor
    self.timeControl = timeControl
  }
}

public enum GamePhase: Equatable, Sendable {
  case notStarted
  case userTurn
  case botThinking
  /// Play Coach is checking the user's move.
  case coachChecking
  /// Play Coach paused the game after a mistake (see `coachPause`).
  case coachPaused
  case over(GameResult)
}

/// Runs one game against a bot: input, rules, clock, bot replies, premoves,
/// sounds, logging and saving. Views only render its state and forward gestures.
@MainActor
@Observable
public final class GameController {
  public private(set) var session: GameSession
  public private(set) var interaction = BoardInteraction()
  public var annotations = AnnotationLayer()
  public private(set) var clock: ChessClock
  public private(set) var phase: GamePhase = .notStarted
  public private(set) var viewPly = 0
  public private(set) var pendingPromotion: Premove?
  public var flipped: Bool
  /// Play Coach state.
  public private(set) var coachPause: CoachPause?
  public private(set) var nudge: String?
  public private(set) var hintText: String?
  public private(set) var hintLevel = 0
  public var isCoached: Bool { coach != nil }

  public let config: PlayConfig
  public let bot: BotPlayer
  public nonisolated let gameID = UUID()

  @ObservationIgnored private let telemetry: Telemetry
  @ObservationIgnored private let store: GameStore?
  @ObservationIgnored private let sounds: SoundSink
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let minimumBotThink: Duration
  @ObservationIgnored private var botTask: Task<Void, Never>?
  @ObservationIgnored private var startedAt = Date()
  @ObservationIgnored private var lowTimeWarned = false
  @ObservationIgnored private var gameStep: StepContext?
  @ObservationIgnored private let coach: CoachAdvisor?
  @ObservationIgnored private var movesSinceNudge = 99
  @ObservationIgnored private var hintBest: String?

  public init(
    config: PlayConfig,
    bot: BotPlayer,
    telemetry: Telemetry,
    store: GameStore?,
    sounds: SoundSink,
    startFEN: String = GameSession.standardFEN,
    minimumBotThink: Duration = .milliseconds(450),
    coach: CoachAdvisor? = nil,
    now: @escaping () -> Date = Date.init
  ) {
    self.coach = coach
    self.config = config
    self.bot = bot
    self.telemetry = telemetry
    self.store = store
    self.sounds = sounds
    self.now = now
    self.minimumBotThink = minimumBotThink
    session = GameSession(startFEN: startFEN)
    clock = ChessClock(control: config.timeControl)
    flipped = config.userColor == .black
  }

  // MARK: - Derived state

  public var userColor: Piece.Color { config.userColor }
  public var isOver: Bool { if case .over = phase { true } else { false } }
  public var result: GameResult? { if case .over(let r) = phase { r } else { nil } }
  public var isViewingLatest: Bool { viewPly == session.history.count }
  public var displayedFEN: String { session.fen(atPly: viewPly) }
  public var displayedPosition: Position { Position(fen: displayedFEN) ?? session.position }
  public var highlights: BoardHighlights { BoardHighlights.make(session: session, ply: viewPly, interaction: interaction) }

  public func remaining(_ color: Piece.Color) -> TimeInterval { clock.remaining(color, at: now()) }
  public func isLowTime(_ color: Piece.Color) -> Bool { clock.isLow(color, at: now()) }

  // MARK: - Lifecycle

  public func start() {
    guard phase == .notStarted else { return }
    startedAt = now()
    telemetry.event(
      "game.start",
      metadata: [
        "game": .string(gameID.uuidString), "opponent": .string(bot.kind),
        "userColor": .string(userColor.rawValue), "time": .string(config.timeControl.pgnTag),
      ])
    sounds.play(.gameStart)
    if config.timeControl.isTimed { clock.start(session.sideToMove, at: now()) }
    advanceTurn()
  }

  /// Call ~10×/s from the view: detects flag fall and the low-time warning.
  public func tick() {
    guard !isOver, config.timeControl.isTimed else { return }
    let t = now()
    if let flagged = clock.flagged(at: t) {
      session.flag(flagged)
      finish()
      return
    }
    if !lowTimeWarned, clock.isLow(userColor, at: t) {
      lowTimeWarned = true
      sounds.play(.lowTime)
      telemetry.event("game.lowTime", metadata: ["remaining": .double(clock.remaining(userColor, at: t))])
    }
  }

  /// Awaits the bot's pending reply (tests and previews).
  public func waitForBot() async {
    await botTask?.value
  }

  // MARK: - Input

  public func tap(_ square: Square) {
    guard isViewingLatest, !isOver, pendingPromotion == nil else { return }
    handle(interaction.tap(square, session: session, userColor: userColor))
  }

  @discardableResult
  public func dragBegan(_ square: Square) -> Bool {
    guard isViewingLatest, !isOver, pendingPromotion == nil else { return false }
    return interaction.dragBegan(at: square, session: session, userColor: userColor)
  }

  public func dragEnded(at square: Square?) {
    handle(interaction.dragEnded(at: square, session: session, userColor: userColor))
  }

  public func dragCancelled() {
    interaction.dragCancelled()
  }

  public func choosePromotion(_ kind: Piece.Kind) {
    guard let pending = pendingPromotion else { return }
    pendingPromotion = nil
    playUserMove(from: pending.from, to: pending.to, promotion: kind)
  }

  public func cancelPromotion() {
    pendingPromotion = nil
  }

  public func resign() {
    guard !isOver, phase != .notStarted else { return }
    session.resign(userColor)
    finish()
  }

  /// The bot accepts a draw only in a long, level game (move 30+, material within a pawn).
  @discardableResult
  public func offerDraw() -> Bool {
    guard !isOver else { return false }
    let accepted = session.history.count >= 60 && abs(session.materialBalance) <= 1
    telemetry.event("game.drawOffer", metadata: ["accepted": .bool(accepted), "ply": .int(session.history.count)])
    if accepted {
      session.agreeDraw()
      finish()
    }
    return accepted
  }

  public func flip() { flipped.toggle() }

  public func stepBack() { viewPly = max(0, viewPly - 1) }
  public func stepForward() { viewPly = min(session.history.count, viewPly + 1) }
  public func jumpToLatest() { viewPly = session.history.count }
  public func jump(toPly ply: Int) { viewPly = max(0, min(session.history.count, ply)) }

  // MARK: - Turn flow

  private func handle(_ result: InteractionResult) {
    switch result {
    case .move(let from, let to):
      if session.isPromotion(from: from, to: to) {
        pendingPromotion = Premove(from: from, to: to)
      } else {
        playUserMove(from: from, to: to, promotion: nil)
      }
    case .premoveQueued(let from, let to):
      sounds.play(.premove)
      telemetry.event("game.premove", metadata: ["from": .string(from.notation), "to": .string(to.notation)])
    default:
      break
    }
  }

  /// Ends the game if the side to move has already run out of time.
  private func flagIfOutOfTime() -> Bool {
    guard config.timeControl.isTimed, let flagged = clock.flagged(at: now()) else { return false }
    session.flag(flagged)
    finish()
    return true
  }

  private func playUserMove(from: Square, to: Square, promotion: Piece.Kind?) {
    guard phase == .userTurn, !flagIfOutOfTime() else { return }
    guard case .applied(let played) = session.apply(from: from, to: to, promotion: promotion) else {
      sounds.play(.illegal)
      return
    }
    afterMove(played, by: "user")
  }

  // MARK: - Play Coach

  /// Undo the mistake and try again.
  public func takeBack() {
    guard coachPause != nil else { return }
    session.undo()
    coachPause = nil
    annotations = AnnotationLayer()
    viewPly = session.history.count
    phase = .userTurn
    telemetry.event("coach.takeback")
  }

  /// Keep the move and let the game go on.
  public func continueGame() {
    guard coachPause != nil else { return }
    coachPause = nil
    annotations = AnnotationLayer()
    advanceTurn()
  }

  /// Draw the better move on the board.
  public func showBetterMove() {
    guard let pause = coachPause, let m = UCIMove(pause.bestUCI) else { return }
    annotations.arrows = [Arrow(from: m.from, to: m.to, color: .green)]
  }

  /// Hint ladder for the user's turn: piece → highlight → move.
  public func hint() async {
    guard phase == .userTurn, let coach else { return }
    if hintBest == nil {
      hintBest = try? await coach.assess(fen: session.position.fen).bestUCI
    }
    guard let best = hintBest.flatMap(UCIMove.init), let piece = session.position.piece(at: best.from) else { return }
    hintLevel = min(3, hintLevel + 1)
    switch hintLevel {
    case 1: hintText = "Look at your \(FactExtractor.name(of: piece.kind))s."
    case 2:
      hintText = "This piece has a strong move."
      annotations.circles = [best.from: .blue]
    default:
      hintText = "Here's the move."
      annotations.circles = [:]
      annotations.arrows = [Arrow(from: best.from, to: best.to, color: .green)]
    }
    telemetry.event("coach.hint", metadata: ["level": .int(hintLevel)])
  }

  private func coachCheck(_ played: PlayedMove) {
    guard let coach else { return advanceTurn() }
    phase = .coachChecking
    let before = session.fen(atPly: session.history.count - 1)
    let after = session.position.fen
    Task { [weak self] in
      let a = try? await coach.assess(fen: before)
      let b = try? await coach.assess(fen: after)
      guard let self, self.phase == .coachChecking else { return }
      guard let a, let b else { return self.advanceTurn() }
      let bestEP = a.winPercent / 100
      let playedEP = 1 - b.winPercent / 100
      let isBest = a.bestUCI == played.uci
      let loss = isBest ? 0 : max(0, bestEP - playedEP)
      let label = MoveClassifier.base(loss: loss, isBest: isBest)
      guard label == .mistake || label == .blunder else { return self.advanceTurn() }
      let sheet = FactExtractor.sheet(fen: before, played: played.uci, bestLine: [a.bestUCI], punishLine: [b.bestUCI], ply: self.session.history.count)
      let bestSAN = FactExtractor.sanLine(fen: before, ucis: [a.bestUCI]).first ?? a.bestUCI
      self.coachPause = CoachPause(
        label: label, playedSAN: played.san, bestUCI: a.bestUCI, bestSAN: bestSAN,
        explanation: sheet.map { Explainer.explain($0, as: label, isUser: true) } ?? "There was a better move.")
      self.phase = .coachPaused
      self.telemetry.event("coach.pause", metadata: ["label": .string(label.rawValue), "san": .string(played.san)])
    }
  }

  /// After the bot moves: nudge the user to look for threats when something is loose
  /// or the bot's move set up a tactic (at most every third move).
  private func coachNudge(_ played: PlayedMove) {
    movesSinceNudge += 1
    guard coach != nil, movesSinceNudge >= 3 else { return }
    let before = session.fen(atPly: session.history.count - 1)
    let threats: Set<Motif> = [.fork, .pin, .skewer, .discoveredAttack, .mateThreat]
    let facts = FactExtractor.moveFacts(fen: before, uci: played.uci)
    let hanging = FactExtractor.hangingPieces(fen: session.position.fen, of: userColor)
    if !hanging.isEmpty {
      nudge = "Careful — something of yours is loose. Check before you move."
    } else if let facts, !threats.isDisjoint(with: facts.motifs) {
      nudge = "\(played.san) set up a threat. What does it attack?"
    } else {
      return
    }
    movesSinceNudge = 0
    telemetry.event("coach.nudge")
  }

  private func afterMove(_ played: PlayedMove, by mover: String) {
    if config.timeControl.isTimed {
      clock.press(played.color, at: now())
      session.setClockAfterLastMove(clock.remaining(played.color, at: now()))
    }
    viewPly = session.history.count
    annotations.clearUser()
    sounds.play(SoundEvent.forMove(played, gameOver: session.isOver))
    telemetry.event(
      "game.move",
      metadata: [
        "game": .string(gameID.uuidString), "by": .string(mover), "san": .string(played.san),
        "ply": .int(session.history.count),
      ])
    hintLevel = 0
    hintText = nil
    hintBest = nil
    if mover == "user" { nudge = nil }
    if session.isOver {
      finish()
    } else if mover == "user", coach != nil {
      coachCheck(played)
    } else {
      if mover == "bot" { coachNudge(played) }
      advanceTurn()
    }
  }

  private func advanceTurn() {
    if session.sideToMove == userColor {
      phase = .userTurn
      playPremoveIfAny()
    } else {
      phase = .botThinking
      requestBotMove()
    }
  }

  private func playPremoveIfAny() {
    guard let premove = interaction.takePremove() else { return }
    let promotion: Piece.Kind? = session.isPromotion(from: premove.from, to: premove.to) ? .queen : nil
    if session.legalTargets(from: premove.from).contains(premove.to) {
      playUserMove(from: premove.from, to: premove.to, promotion: promotion)
    } else {
      telemetry.event("game.premoveDiscarded")
    }
  }

  private func requestBotMove() {
    let fen = session.position.fen
    let ply = session.history.count
    botTask = Task { [weak self, bot, minimumBotThink, telemetry] in
      let started = ContinuousClock.now
      let uci: String?
      do {
        uci = try await telemetry.step("game.botTurn", metadata: ["ply": .int(ply)]) { _ in
          try await bot.move(fen: fen)
        }
      } catch {
        uci = nil
      }
      let elapsed = ContinuousClock.now - started
      if elapsed < minimumBotThink { try? await Task.sleep(for: minimumBotThink - elapsed) }
      self?.applyBotMove(uci, expectedPly: ply)
    }
  }

  private func applyBotMove(_ uci: String?, expectedPly: Int) {
    guard !isOver, session.history.count == expectedPly, !flagIfOutOfTime() else { return }
    var outcome: ApplyOutcome = .illegal
    if let uci { outcome = session.apply(uci: uci) }
    if case .applied(let played) = outcome {
      afterMove(played, by: "bot")
      return
    }
    // Engine failed or returned junk: keep the game going with any legal move.
    telemetry.event("game.botFallback", metadata: ["uci": .string(uci ?? "nil")])
    if let fallback = anyLegalMove(), case .applied(let played) = session.apply(from: fallback.0, to: fallback.1, promotion: .queen) {
      afterMove(played, by: "bot")
    }
  }

  private func anyLegalMove() -> (Square, Square)? {
    for piece in session.position.pieces where piece.color == session.sideToMove {
      if let target = session.legalTargets(from: piece.square).first { return (piece.square, target) }
    }
    return nil
  }

  private func finish() {
    guard let result = session.result else { return }
    botTask?.cancel()
    if config.timeControl.isTimed { clock.pause(at: now()) }
    interaction.reset()
    pendingPromotion = nil
    phase = .over(result)
    viewPly = session.history.count
    sounds.play(.gameEnd)
    save(result)
  }

  private func save(_ result: GameResult) {
    let userName = "You"
    let white = userColor == .white ? userName : bot.name
    let black = userColor == .black ? userName : bot.name
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.calendar = Calendar(identifier: .gregorian)
    dateFormatter.dateFormat = "yyyy.MM.dd"
    let pgn = session.pgn(tags: [
      "Event": "ChessCoach", "Site": "ChessCoach iOS", "Date": dateFormatter.string(from: startedAt),
      "White": white, "Black": black, "TimeControl": config.timeControl.pgnTag,
      "Termination": result.termination.displayName,
    ])
    let record = GameRecord(
      id: gameID.uuidString, source: .local, pgn: pgn, white: white, black: black,
      userColor: userColor.rawValue, result: result.pgnResult, termination: result.termination.rawValue,
      timeControl: config.timeControl.pgnTag, opponentKind: bot.kind, startedAt: startedAt, endedAt: now())
    do {
      try store?.save(record)
    } catch {
      telemetry.event("game.saveFailed", metadata: ["error": .string(String(describing: error))])
    }
    telemetry.event(
      "game.end",
      metadata: [
        "game": .string(gameID.uuidString), "result": .string(result.pgnResult),
        "termination": .string(result.termination.rawValue), "plies": .int(session.history.count),
      ])
  }
}
