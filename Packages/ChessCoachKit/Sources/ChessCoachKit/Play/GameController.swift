import ChessKit
import Foundation
import Observation

public enum Opponent: Hashable, Sendable {
  case maia(rating: Int)
  case stockfish(level: Int)
  /// Claude chooses teaching moves from engine-vetted candidates (Maia-like offline).
  case teaching
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
  /// The latest line from the coach in your corner (spoken by the app). `id` changes per line.
  public private(set) var coachLine: (id: Int, text: String)?
  public var hasVoiceCoach: Bool { voice != nil }
  /// The bot's own explanation per ply (1-based, as in `viewPly`), when it gave one.
  public private(set) var botReasons: [Int: String] = [:]

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
  @ObservationIgnored private var hinting = false
  @ObservationIgnored private let voice: CoachAdvisor?
  /// Engine's best move in the position you're facing (for the coach's reaction afterwards).
  @ObservationIgnored private var voiceBest: (ply: Int, uci: String)?
  @ObservationIgnored private var userTurns = 0
  /// Bumped by undo so engine/coach work started before it is dropped.
  @ObservationIgnored private var generation = 0

  public init(
    config: PlayConfig,
    bot: BotPlayer,
    telemetry: Telemetry,
    store: GameStore?,
    sounds: SoundSink,
    startFEN: String = GameSession.standardFEN,
    minimumBotThink: Duration = .milliseconds(450),
    coach: CoachAdvisor? = nil,
    voice: CoachAdvisor? = nil,
    now: @escaping () -> Date = Date.init
  ) {
    self.coach = coach
    self.voice = voice
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

  private var coachBusy: Bool { phase == .coachChecking || phase == .coachPaused }

  public func tap(_ square: Square) {
    guard isViewingLatest, !isOver, pendingPromotion == nil, !coachBusy else { return }
    handle(interaction.tap(square, session: session, userColor: userColor))
  }

  @discardableResult
  public func dragBegan(_ square: Square) -> Bool {
    guard isViewingLatest, !isOver, pendingPromotion == nil, !coachBusy else { return false }
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

  // MARK: - Undo

  /// Untimed games only: a clock can't be rewound fairly.
  public var canUndo: Bool {
    !isOver && phase != .notStarted && !config.timeControl.isTimed && session.history.contains { $0.color == userColor }
  }

  /// Takes back your last move and anything the bot played after it.
  public func undoMove() {
    guard canUndo, let mine = session.history.lastIndex(where: { $0.color == userColor }) else { return }
    generation += 1
    botTask?.cancel()
    botTask = nil
    session.undo(session.history.count - mine)
    interaction.reset()
    coachPause = nil
    annotations = AnnotationLayer()
    nudge = nil
    hintText = nil
    hintLevel = 0
    hintBest = nil
    coachLine = nil
    pendingPromotion = nil
    botReasons = botReasons.filter { $0.key <= session.history.count }
    viewPly = session.history.count
    phase = .userTurn
    telemetry.event("game.undo", metadata: ["ply": .int(session.history.count)])
  }

  // MARK: - Play Coach

  /// Undo the mistake and try again.
  public func takeBack() {
    guard coachPause != nil, !isOver else { return }
    session.undo()
    interaction.reset()  // drop anything queued for the position after the mistake
    coachPause = nil
    annotations = AnnotationLayer()
    viewPly = session.history.count
    phase = .userTurn
    telemetry.event("coach.takeback")
  }

  /// Keep the move and let the game go on.
  public func continueGame() {
    guard coachPause != nil, !isOver else { return }
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
    guard phase == .userTurn, let coach, !hinting else { return }
    hinting = true
    defer { hinting = false }
    let ply = session.history.count
    if hintBest == nil {
      let best = try? await coach.assess(fen: session.position.fen).bestUCI
      // The user may have moved while the engine thought; drop a stale answer.
      guard session.history.count == ply, phase == .userTurn else { return }
      hintBest = best
    }
    nudge = nil
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
    let gen = generation
    Task { [weak self] in
      let a = try? await coach.assess(fen: before)
      let b = try? await coach.assess(fen: after)
      guard let self, self.phase == .coachChecking, self.generation == gen else { return }
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
    if mover == "user" {
      nudge = nil
      coachLine = nil  // the prompt was about the position you just left
      voiceReact(played)
    }
    if session.isOver {
      finish()
    } else if mover == "user", coach != nil {
      coachCheck(played)
    } else {
      if mover == "bot", voice == nil { coachNudge(played) }
      advanceTurn()
    }
  }

  private func advanceTurn() {
    if session.sideToMove == userColor {
      phase = .userTurn
      voicePrompt()
      playPremoveIfAny()
    } else {
      phase = .botThinking
      requestBotMove()
    }
  }

  // MARK: - Coach in your corner

  private func say(_ text: String) {
    coachLine = (id: (coachLine?.id ?? 0) + 1, text: text)
    telemetry.event("coach.voice", metadata: ["text": .string(text)])
  }

  /// On your turn: find the engine's best move, then nudge toward the idea (never the move).
  private func voicePrompt() {
    guard let voice else { return }
    userTurns += 1
    let ply = session.history.count
    let fen = session.position.fen
    let last = session.lastMove
    let before = session.fen(atPly: ply - 1)
    let turn = userTurns
    let gen = generation
    Task { [weak self] in
      let best = try? await voice.assess(fen: fen).bestUCI
      guard let self, self.generation == gen, self.session.history.count == ply, !self.isOver, let best else { return }
      self.voiceBest = (ply, best)
      // Play Coach's nudge banner already covers threats; the voice adds tactics and advice.
      guard let last, last.color != self.userColor else { return }
      if let line = CoachVoice.prompt(fenBeforeOpponent: before, opponentMove: last.uci, fenNow: fen, best: best, turn: turn) {
        self.say(line)
      }
    }
  }

  private func voiceReact(_ played: PlayedMove) {
    guard voice != nil else { return }
    let ply = session.history.count - 1
    let best = voiceBest?.ply == ply ? voiceBest?.uci : nil
    // Play Coach pauses on real mistakes itself; the voice only praises or warns there.
    let line = CoachVoice.react(fenBefore: session.fen(atPly: ply), played: played.uci, bestBefore: coach == nil ? best : nil)
    if let line { say(line) }
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
    let gen = generation
    botTask = Task { [weak self, bot, minimumBotThink, telemetry] in
      let started = ContinuousClock.now
      let pick: (uci: String, why: String?)?
      do {
        pick = try await telemetry.step("game.botTurn", metadata: ["ply": .int(ply)]) { _ in
          try await bot.explainedMove(fen: fen)
        }
      } catch {
        pick = nil
      }
      let elapsed = ContinuousClock.now - started
      if elapsed < minimumBotThink { try? await Task.sleep(for: minimumBotThink - elapsed) }
      guard let self, self.generation == gen, !Task.isCancelled else { return }
      self.botReasons[ply + 1] = pick?.why
      self.applyBotMove(pick?.uci, expectedPly: ply)
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
    coachPause = nil
    hintText = nil
    nudge = nil
    annotations = AnnotationLayer()
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
