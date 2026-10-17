import ChessKit
import Foundation
import Observation

/// Drives the Game Review screen: browsing, the key-moment walkthrough, and
/// "Retry" (find the better move yourself, with a hint ladder).
@MainActor
@Observable
public final class ReviewController {
  public enum Mode: Equatable {
    case browse
    case retry(RetryState)
  }

  public struct RetryState: Equatable {
    /// The ply of the mistake being retried (position shown is the one before it).
    public var ply: Int
    public var attempts = 0
    public var hintLevel = 0
    public var solved = false
    public var revealed = false
    public var lastWrong: String?
  }

  public let analysis: GameAnalysis
  public let session: GameSession
  public private(set) var ply: Int = 0
  public private(set) var mode: Mode = .browse
  public private(set) var interaction = BoardInteraction()
  public private(set) var momentIndex: Int?

  /// Playing a line out on the board from the position before the current move:
  /// your move and its punishment, or the better move and its line.
  public struct LinePreview: Equatable {
    public var moves: [String]
    public var step: Int
    public var isBetter: Bool
  }
  public private(set) var line: LinePreview?

  @ObservationIgnored private let telemetry: Telemetry

  public init(analysis: GameAnalysis, session: GameSession, telemetry: Telemetry) {
    self.analysis = analysis
    self.session = session
    self.telemetry = telemetry
  }

  // MARK: - Derived

  public var userColor: Piece.Color { analysis.userColor == "white" ? .white : .black }
  public var keyMoments: [Int] { analysis.keyMoments }
  public var currentMove: MoveAnalysis? { ply > 0 && ply <= analysis.moves.count ? analysis.moves[ply - 1] : nil }

  public var retryState: RetryState? {
    if case .retry(let state) = mode { return state }
    return nil
  }

  /// Why the current move was a mistake (nil for good moves).
  public var insight: MoveInsight? { currentMove.flatMap(MoveInsight.make) }

  /// The line position after `step` moves.
  private func lineGame(_ l: LinePreview) -> GameSession {
    var g = GameSession(startFEN: session.fen(atPly: ply - 1))
    for uci in l.moves.prefix(l.step) { g.apply(uci: uci) }
    return g
  }

  /// FEN shown on the board.
  public var displayedFEN: String {
    if let line { return lineGame(line).position.fen }
    if let retry = retryState {
      if retry.solved || retry.revealed, let best = analysis.moves[retry.ply - 1].bestUCI {
        var s = GameSession(startFEN: session.fen(atPly: retry.ply - 1))
        s.apply(uci: best)
        return s.position.fen
      }
      return session.fen(atPly: retry.ply - 1)
    }
    return session.fen(atPly: ply)
  }

  public var highlights: BoardHighlights {
    if let line {
      var h = BoardHighlights()
      if let last = lineGame(line).history.last { h.lastMove = [last.move.start, last.move.end] }
      return h
    }
    if let retry = retryState {
      var h = BoardHighlights()
      if let retryMoveFrom = retry.revealed || retry.solved ? analysis.moves[retry.ply - 1].bestUCI.flatMap(UCIMove.init) : nil {
        h.lastMove = [retryMoveFrom.from, retryMoveFrom.to]
      }
      h.selected = interaction.selected
      h.targets = interaction.legalTargets
      return h
    }
    return BoardHighlights.make(session: session, ply: ply, interaction: BoardInteraction())
  }

  /// Arrows: green = the better move, red = how the played move gets punished.
  public var annotations: AnnotationLayer {
    var layer = AnnotationLayer()
    if let line {
      if line.step < line.moves.count, let next = UCIMove(line.moves[line.step]) {
        let mine = line.step % 2 == 0
        layer.arrows.append(Arrow(from: next.from, to: next.to, color: line.isBetter ? (mine ? .green : .blue) : (mine ? .blue : .red)))
      }
      return layer
    }
    if let retry = retryState {
      let move = analysis.moves[retry.ply - 1]
      if retry.hintLevel >= 2, !retry.revealed, !retry.solved, let best = move.bestUCI.flatMap(UCIMove.init) {
        layer.circles[best.from] = .blue
      }
      return layer
    }
    guard let move = currentMove else { return layer }
    if move.label.isError, let best = move.bestUCI.flatMap(UCIMove.init) {
      layer.arrows.append(Arrow(from: best.from, to: best.to, color: .green))
    }
    if move.label.isError, let punish = move.facts?.punish.flatMap({ UCIMove($0.uci) }) {
      layer.arrows.append(Arrow(from: punish.from, to: punish.to, color: .red))
    }
    return layer
  }

  /// The coach bubble text for what's on screen.
  public var coachText: String {
    if let line {
      guard line.step > 0 else {
        return line.isBetter ? "The better move, step by step. Tap ▶ to play it." : "Your move and how it gets punished. Tap ▶ to play it."
      }
      var before = GameSession(startFEN: session.fen(atPly: ply - 1))
      for uci in line.moves.prefix(line.step - 1) { before.apply(uci: uci) }
      let text = Explainer.reason(fen: before.position.fen, uci: line.moves[line.step - 1]) ?? ""
      return line.step == line.moves.count ? text + " That's the end of the line." : text
    }
    if let retry = retryState {
      let move = analysis.moves[retry.ply - 1]
      if retry.solved { return "That's it! \(move.facts?.best?.san ?? "That move") was the move. \(move.explanation)" }
      if retry.revealed { return "The move was \(move.facts?.best?.san ?? move.bestUCI ?? "—"). \(move.explanation)" }
      if let wrong = retry.lastWrong { return "\(wrong) isn't it. \(hintText(level: retry.hintLevel, move: move))" }
      return retry.hintLevel > 0 ? hintText(level: retry.hintLevel, move: move) : "Find a better move than \(move.san)."
    }
    guard let move = currentMove else {
      return analysis.openingName.map { "Opening: \($0). Tap Start Review to walk through the key moments." }
        ?? "Tap Start Review to walk through the key moments."
    }
    return move.explanation
  }

  // MARK: - Browsing

  public func goTo(ply newPly: Int) {
    endRetry()
    line = nil
    ply = max(0, min(analysis.moves.count, newPly))
    momentIndex = keyMoments.firstIndex(of: ply)
  }

  public func stepForward() { goTo(ply: ply + 1) }
  public func stepBack() { goTo(ply: ply - 1) }

  public func startReview() {
    telemetry.event("review.start", metadata: ["game": .string(analysis.gameID), "moments": .int(keyMoments.count)])
    guard let first = keyMoments.first else {
      goTo(ply: analysis.moves.count)
      return
    }
    goTo(ply: first)
    momentIndex = 0
  }

  public func nextMoment() {
    let next = keyMoments.first { $0 > ply }
    if let next { goTo(ply: next) } else { goTo(ply: analysis.moves.count) }
  }

  public func previousMoment() {
    if let previous = keyMoments.last(where: { $0 < ply }) { goTo(ply: previous) }
  }


  // MARK: - Lines

  /// Plays your move and its punishment (`better: false`) or the better line from the position before the move.
  public func playLine(better: Bool) {
    guard let insight else { return }
    endRetry()
    line = LinePreview(moves: better ? insight.betterLine : insight.playedLine, step: 0, isBetter: better)
    telemetry.event("review.line", metadata: ["ply": .int(ply), "better": .bool(better)])
  }

  public func lineForward() {
    guard var l = line, l.step < l.moves.count else { return }
    l.step += 1
    line = l
  }

  public func lineBack() {
    guard var l = line, l.step > 0 else { return }
    l.step -= 1
    line = l
  }

  public func endLine() { line = nil }

  // MARK: - Retry

  /// Can the user retry the move at the current ply?
  public var canRetry: Bool {
    guard let move = currentMove else { return false }
    return move.label.isError && move.bestUCI != nil
  }

  public func retry() {
    guard canRetry else { return }
    line = nil
    interaction.reset()
    mode = .retry(RetryState(ply: ply))
    telemetry.event("review.retry", metadata: ["ply": .int(ply)])
  }

  public func endRetry() {
    if case .retry = mode { mode = .browse }
    interaction.reset()
  }

  public func hint() {
    guard var state = retryState, !state.solved, !state.revealed else { return }
    state.hintLevel = min(3, state.hintLevel + 1)
    if state.hintLevel == 3 { state.revealed = true }
    mode = .retry(state)
  }

  public func reveal() {
    guard var state = retryState else { return }
    state.revealed = true
    mode = .retry(state)
  }

  public func retryTap(_ square: Square) {
    guard var state = retryState, !state.solved, !state.revealed else { return }
    let s = GameSession(startFEN: session.fen(atPly: state.ply - 1))
    let result = interaction.tap(square, session: s, userColor: s.sideToMove)
    guard case .move(let from, let to) = result else { return }
    attempt(from: from, to: to, in: s, state: &state)
  }

  public func retryDrag(from: Square, to: Square) {
    guard var state = retryState, !state.solved, !state.revealed else { return }
    let s = GameSession(startFEN: session.fen(atPly: state.ply - 1))
    guard s.legalTargets(from: from).contains(to) else { return }
    interaction.reset()
    attempt(from: from, to: to, in: s, state: &state)
  }

  private func attempt(from: Square, to: Square, in s: GameSession, state: inout RetryState) {
    let move = analysis.moves[state.ply - 1]
    var copy = s
    let promo: Piece.Kind? = copy.isPromotion(from: from, to: to) ? .queen : nil
    guard case .applied(let played) = copy.apply(from: from, to: to, promotion: promo) else { return }
    state.attempts += 1
    let accepted = Set(move.goodMoves + [move.bestUCI].compactMap { $0 })
    if accepted.contains(played.uci) {
      state.solved = true
      state.lastWrong = nil
    } else {
      state.lastWrong = played.san
      // A wrong try earns the idea hint, never the piece: that one is only shown when asked for.
      state.hintLevel = max(state.hintLevel, 1)
    }
    telemetry.event("review.attempt", metadata: ["ply": .int(state.ply), "move": .string(played.uci), "ok": .bool(state.solved)])
    mode = .retry(state)
  }

  private func hintText(level: Int, move: MoveAnalysis) -> String {
    let best = move.facts?.best
    switch level {
    case 0: return "Find a better move than \(move.san)."
    case 1:
      if let motif = best?.motifs.first(where: { $0 != .check }) { return "Hint: look for a \(motif.displayName.lowercased())." }
      if !(move.facts?.hangingAfter.isEmpty ?? true) { return "Hint: something of yours is loose — keep it safe." }
      if move.mistakeType == .positional { return "Hint: no tactic here. Which of your pieces is doing the least?" }
      return "Hint: check every check, capture and threat first."
    default:
      if let from = move.bestUCI?.prefix(2) { return "Hint: move the piece on \(from)." }
      return "Hint: look at your most active piece."
    }
  }
}
