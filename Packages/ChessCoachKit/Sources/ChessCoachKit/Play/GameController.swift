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

/// A line from the coach: `headline` is spoken (a fixed, pre-recorded line); `text` is shown.
public struct CoachLine: Equatable, Sendable {
  public var id: Int
  public var headline: String?
  public var text: String
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
  public private(set) var coachLine: CoachLine? {
    didSet {
      // Remember what the coach said at each ply, so stepping back shows it again.
      let ply = session.history.count
      coachLog = coachLog.filter { $0.key <= ply }
      if let coachLine { coachLog[ply] = coachLine }
    }
  }
  /// Coach lines by the ply they were said at (moves played so far).
  private var coachLog: [Int: CoachLine] = [:]

  /// The coach line for the move on screen: the live one, or what the coach said back then.
  public var shownCoachLine: CoachLine? {
    if isViewingLatest { return coachLine }
    return coachLog.filter { $0.key <= viewPly }.max { $0.key < $1.key }?.value
  }
  /// Coach games: opening (following your repertoire) → middlegame → endgame.
  public private(set) var stage: GamePhaseKind = .opening
  /// Your repertoire line, once the game has picked one.
  public var openingName: String? { openingDone ? nil : guide?.name(ucis) }
  public var hasVoiceCoach: Bool { voice != nil }
  /// The bot's own explanation per ply (1-based, as in `viewPly`), when it gave one.
  public private(set) var botReasons: [Int: String] = [:]
  /// What this coach game trains (shown and said at the start).
  public let focus: CoachFocus?
  /// This game's slips, by kind (the app folds them into your weakness tally).
  public private(set) var tally = WeaknessTally()
  /// Called once when the game ends.
  @ObservationIgnored public var onFinished: ((WeaknessTally) -> Void)?

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
  @ObservationIgnored private let writer: CoachWriter?
  @ObservationIgnored private let guide: OpeningGuide?
  /// The learner's long-run record, in words (for the AI coach).
  @ObservationIgnored private let growth: String
  /// Left the repertoire, or its line ended.
  @ObservationIgnored private var openingDone = false
  /// Your win% right after your last move (to spot the opponent slipping).
  @ObservationIgnored private var afterMoveWin: (ply: Int, win: Double)?
  /// Mid-way through a forced mate the coach pointed at.
  @ObservationIgnored private var mateRun = false
  /// Interruption budget: the AI coach's own hold-ups are spaced out, and "they slipped" is rare.
  @ObservationIgnored private var lastVetPausePly = -99
  @ObservationIgnored private var opportunitiesLeft = 2

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
    focus: CoachFocus? = nil,
    writer: CoachWriter? = nil,
    opening: OpeningGuide? = nil,
    growth: String = "",
    now: @escaping () -> Date = Date.init
  ) {
    self.focus = focus
    self.writer = writer
    self.guide = opening
    self.growth = growth
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
    if focus != nil { gameIntro() }
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

  /// Any game in progress. Clocks keep the time already spent (they aren't rewound).
  public var canUndo: Bool {
    !isOver && phase != .notStarted && session.history.contains { $0.color == userColor }
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
    mateRun = false
    openingDone = guide.map { $0.follow(ucis).isEmpty } ?? true
    phase = .userTurn
    if config.timeControl.isTimed, clock.running != userColor {
      clock.pause(at: now())
      clock.start(userColor, at: now())
    }
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
    guard let pause = coachPause, !isOver else { return }
    if pause.kind == .leftBook { openingDone = true }
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
    if hintBest == nil, focus != nil, !openingDone, let book = guide?.nextMoves(ucis).first {
      hintBest = book.uci
    }
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
    let ply = session.history.count
    let before = session.fen(atPly: ply - 1)
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
      self.afterMoveWin = (ply, playedEP * 100)
      var hold = HoldUp.check(fenBefore: before, played: played.uci, label: label, focus: self.focus)
      // A longer forced mate the engine saw and the move threw away (the opponent isn't getting mated now).
      let stillMating = (b.mate ?? 0) < 0
      if hold == nil || hold?.kind == .mistake || hold?.kind == .blunder, let m = a.mate, m > 1, !stillMating {
        hold = HoldUp.missedForcedMate
      }
      // The AI coach vets every other non-best move against the learner's goals.
      var aiText: String?
      if hold == nil, let writer = self.writer, !isBest, loss >= 0.02, ply - self.lastVetPausePly >= 6 {
        let m = self.moment(.vet, fen: before, engine: a, played: played.uci, punish: b.line, label: label, template: "")
        if let verdict = await writer.vet(m), let h = HoldUp.reviewed(verdict.kind) {
          hold = h
          aiText = verdict.text
          self.lastVetPausePly = ply
        }
        guard self.phase == .coachChecking, self.generation == gen else { return }
      }
      guard let hold else { return self.advanceTurn() }
      self.tally.record(hold.kind)
      let bestSAN = FactExtractor.sanLine(fen: before, ucis: [a.bestUCI]).first ?? a.bestUCI
      var explanation = hold.line.replacingOccurrences(of: "Hold up. ", with: "")
      if hold.kind == .mistake || hold.kind == .blunder {
        let sheet = FactExtractor.sheet(fen: before, played: played.uci, bestLine: a.line, punishLine: b.line, ply: ply)
        explanation = sheet.map { Explainer.explain($0, as: label, isUser: true) } ?? "There was a better move."
      } else if hold.kind == .missedMate, let m = a.mate, m > 1 {
        explanation = "Mate in \(m) was there. Look at every check, even the ones that give up material."
      }
      let pause = CoachPause(
        label: label, playedSAN: played.san, bestUCI: a.bestUCI, bestSAN: bestSAN, explanation: aiText ?? explanation, kind: hold.kind)
      self.coachPause = pause
      self.annotations.circles = hold.marks
      self.coachSays(headline: hold.line, text: hold.line)
      self.phase = .coachPaused
      self.telemetry.event("coach.pause", metadata: ["kind": .string(hold.kind.rawValue), "label": .string(label.rawValue), "san": .string(played.san)])
      // The template shows at once; the coach's own words replace it when they arrive.
      if aiText == nil, let writer = self.writer {
        let m = self.moment(.holdUp, fen: before, engine: a, played: played.uci, punish: b.line, label: label, holdUp: hold.kind, template: explanation)
        if let text = await writer.write(m), self.coachPause == pause { self.coachPause?.explanation = text }
      }
    }
  }

  // MARK: - Coach game stages

  private var ucis: [String] { session.history.map(\.uci) }

  /// Start of a coach game: the opening (your repertoire) or straight to the stage the position is in.
  private func gameIntro() {
    if let guide, !guide.nextMoves(ucis).isEmpty {
      stage = .opening
      let text = guide.name(ucis).map { "Your \($0). \(guide.summary(ucis) ?? "")" }
        ?? "Play your repertoire. I'll explain each move and stop you if you leave the line."
      coachSays(headline: CoachVoice.openingStart, text: text)
    } else {
      openingDone = true
      stage = FactExtractor.phase(fen: session.position.fen, ply: session.history.count) == .endgame ? .endgame : .middlegame
      announce(stage, engine: nil)
    }
  }

  /// Your move in the opening: in the line → its idea; out of it → hold up (untimed) or the opening ends.
  /// True when handled (the game goes on, or is paused).
  private func bookMove(_ played: PlayedMove) -> Bool {
    guard focus != nil, !openingDone, let guide else { return false }
    let before = Array(ucis.dropLast())
    let expected = guide.nextMoves(before)
    guard !expected.isEmpty else {
      openingDone = true
      return false
    }
    if let node = expected.first(where: { $0.uci == played.uci }) {
      coachSays(headline: nil, text: node.idea.isEmpty ? "\(played.san). That's your line." : "\(played.san): \(node.idea)")
      return true
    }
    guard coach != nil, let line = expected.first else {
      openingDone = true
      return false
    }
    let name = guide.name(before) ?? "repertoire"
    let pause = CoachPause(
      label: .inaccuracy, playedSAN: played.san, bestUCI: line.uci, bestSAN: line.san,
      explanation: "Your \(name) plays \(line.san) here. \(line.idea)", kind: .leftBook)
    coachPause = pause
    coachSays(headline: HoldUp.leftBook.line, text: HoldUp.leftBook.line)
    phase = .coachPaused
    telemetry.event("coach.pause", metadata: ["kind": .string(HoldUpKind.leftBook.rawValue), "san": .string(played.san)])
    return true
  }

  /// Your turn in a coach game: the opponent's book move, or the stage's prompt.
  private func stagePrompt() {
    let moves = ucis
    if !openingDone, let guide {
      if !guide.nextMoves(moves).isEmpty {
        stage = .opening
        guard let node = guide.lastNode(moves), session.lastMove?.color != userColor else { return }
        if node.trap != nil {
          coachSays(headline: CoachVoice.trapAhead, text: "\(node.san): \(node.idea)")
        } else if node.isDeviation {
          coachSays(headline: CoachVoice.offMainLine, text: "\(node.san): \(node.idea)")
        } else if moves.count == 1, let name = guide.name(moves) {
          coachSays(headline: nil, text: "Your \(name). \(guide.summary(moves) ?? "")")
        }
        return
      }
      openingDone = true
    }
    let next: GamePhaseKind = FactExtractor.phase(fen: session.position.fen, ply: moves.count) == .endgame ? .endgame : .middlegame
    let changed = next != stage
    stage = next
    guard let coach else {
      if changed { announce(next, engine: nil) }
      return
    }
    let fen = session.position.fen
    let ply = moves.count
    let gen = generation
    Task { [weak self] in
      let a = try? await coach.assess(fen: fen)
      guard let self, self.generation == gen, self.session.history.count == ply, self.phase == .userTurn else { return }
      if self.stage == .endgame, let a, let m = a.mate, m > 0, m <= 5 {
        let headline = self.mateRun ? CoachVoice.keepGoing : CoachVoice.mateHere
        self.mateRun = true
        let template = "Mate in \(m). Look at every check, starting with the most forcing."
        self.coachSays(headline: headline, text: template, moment: self.moment(.mateAvailable, fen: fen, engine: a, template: template))
        return
      }
      self.mateRun = false
      if changed {
        self.announce(next, engine: a)
      } else if self.stage == .middlegame, let a, let prev = self.afterMoveWin, prev.ply == ply - 1,
        a.winPercent - prev.win >= 20, a.winPercent >= 60, self.opportunitiesLeft > 0
      {
        self.opportunitiesLeft -= 1
        let template = "Their last move left something. Look at checks, captures and threats."
        self.coachSays(headline: CoachVoice.theySlipped, text: template, moment: self.moment(.opportunity, fen: fen, engine: a, template: template))
      }
    }
  }

  private func announce(_ stage: GamePhaseKind, engine: CoachAssessment?) {
    let fen = session.position.fen
    switch stage {
    case .endgame:
      let template = "Fewer pieces now: bring your king toward the centre, push passed pawns, and check every check for mate."
      coachSays(headline: CoachVoice.endgameStart, text: template, moment: moment(.endgameStart, fen: fen, engine: engine, template: template))
    default:
      let template = focus?.intro ?? "Make a plan: improve your worst piece and watch their threats."
      coachSays(headline: CoachVoice.middlegameStart, text: template, moment: moment(.middlegameStart, fen: fen, engine: engine, template: template))
    }
  }

  private func moment(
    _ kind: CoachMoment.Kind, fen: String, engine: CoachAssessment?, played: String? = nil, punish: [String] = [],
    label: MoveClass? = nil, holdUp: HoldUpKind? = nil, template: String
  ) -> CoachMoment {
    let upTo = played == nil ? session.history.count : session.history.count - 1
    return CoachMoment(
      kind: kind, fen: fen, played: played, engine: engine, punish: punish, label: label, holdUp: holdUp, stage: stage,
      opening: guide?.follow(Array(ucis.prefix(upTo))).first?.repertoire.name, focus: focus, growth: growth,
      recentSAN: session.history.prefix(upTo).map(\.san), template: template)
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
      if focus != nil { countChances(played) }
    }
    if session.isOver {
      finish()
    } else if mover == "user", bookMove(played) {
      if phase != .coachPaused { advanceTurn() }
    } else if mover == "user", coach != nil {
      coachCheck(played)
    } else {
      if mover == "bot", voice == nil, focus == nil { coachNudge(played) }
      advanceTurn()
    }
  }

  private func advanceTurn() {
    if session.sideToMove == userColor {
      phase = .userTurn
      if focus != nil { stagePrompt() } else { voicePrompt() }
      playPremoveIfAny()
    } else {
      phase = .botThinking
      requestBotMove()
    }
  }

  // MARK: - Coach in your corner

  private func say(_ text: String) { coachSays(headline: text, text: text) }

  /// Shows `text` and (in voice mode) speaks `headline`; the AI coach's words replace `text`
  /// when they arrive for `moment`.
  private func coachSays(headline: String?, text: String, moment: CoachMoment? = nil) {
    let id = (coachLine?.id ?? 0) + 1
    coachLine = CoachLine(id: id, headline: headline, text: text)
    telemetry.event("coach.voice", metadata: ["text": .string(headline ?? text)])
    guard let moment, let writer else { return }
    Task { [weak self] in
      guard let better = await writer.write(moment), let self, self.coachLine?.id == id else { return }
      self.coachLine?.text = better
    }
  }

  /// The long-run ledger: chances you took, not just the ones you missed.
  private func countChances(_ played: PlayedMove) {
    let before = session.fen(atPly: session.history.count - 1)
    if played.move.checkState == .checkmate { tally.foundMate += 1 }
    if let free = BoardScan.freeCapture(fen: before), free.piece.square.notation == String(played.uci.dropFirst(2).prefix(2)) {
      tally.foundFree += 1
    }
  }

  /// On your turn: a nudge toward the idea (never the move), said the moment their move lands.
  /// The engine's best is fetched afterwards only for the reaction to your move.
  private func voicePrompt() {
    guard let voice else { return }
    userTurns += 1
    let ply = session.history.count
    let fen = session.position.fen
    if let last = session.lastMove, last.color != userColor,
      let line = CoachVoice.prompt(fenBeforeOpponent: session.fen(atPly: ply - 1), opponentMove: last.uci, fenNow: fen, turn: userTurns)
    {
      say(line)
    }
    guard coach == nil else { return }  // hold-ups cover misses in coach games
    let gen = generation
    Task { [weak self] in
      let best = try? await voice.assess(fen: fen).bestUCI
      guard let self, self.generation == gen, self.session.history.count == ply, let best else { return }
      self.voiceBest = (ply, best)
    }
  }

  private func voiceReact(_ played: PlayedMove) {
    guard voice != nil else { return }
    let ply = session.history.count - 1
    let best = voiceBest?.ply == ply ? voiceBest?.uci : nil
    // Play Coach pauses on real mistakes itself; the voice only praises or warns there.
    let line = CoachVoice.react(fenBefore: session.fen(atPly: ply), played: played.uci, bestBefore: coach == nil ? best : nil)
    // In coach games a loose piece becomes a hold-up instead of a passing warning.
    if let line, coach == nil || !line.hasPrefix("Careful.") { say(line) }
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
    // Coach games: the bot plays your repertoire's lines (a random branch, so you meet them all).
    let book = focus != nil && !openingDone ? guide?.nextMoves(ucis).randomElement() : nil
    botTask = Task { [weak self, bot, minimumBotThink, telemetry] in
      let started = ContinuousClock.now
      let pick: (uci: String, why: String?)?
      if let book {
        pick = (book.uci, book.idea.isEmpty ? nil : book.idea)
      } else {
        pick = try? await telemetry.step("game.botTurn", metadata: ["ply": .int(ply)]) { _ in
          try await bot.explainedMove(fen: fen)
        }
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
    onFinished?(tally)
    onFinished = nil
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
