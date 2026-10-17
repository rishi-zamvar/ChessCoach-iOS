import ChessKit
import Foundation

/// The coach in your corner: short, deterministic spoken lines built from board
/// facts and the engine's best move. Never names the answer before you move —
/// prompts point at the idea ("a fork is there"), reactions can name it after.
public enum CoachVoice {
  static let tactics: [Motif] = [.mate, .fork, .winsMaterial, .pin, .skewer, .discoveredAttack]

  /// Reaction to the move you just played. `bestBefore` is the engine's best in the position you faced.
  public static func react(fenBefore: String, played uci: String, bestBefore: String?) -> String? {
    guard let facts = FactExtractor.moveFacts(fen: fenBefore, uci: uci) else { return nil }
    if facts.motifs.contains(.mate) { return "Checkmate. Beautifully done." }
    if let best = bestBefore, best != uci, let bestFacts = FactExtractor.moveFacts(fen: fenBefore, uci: best),
      let motif = tactics.first(where: bestFacts.motifs.contains)
    {
      return motif == .mate
        ? "Ah. You had checkmate there with \(bestFacts.san)."
        : "Hmm. You missed something. \(bestFacts.san) was \(article(motif))."
    }
    var session = GameSession(startFEN: fenBefore)
    let mover = session.sideToMove
    session.apply(uci: uci)
    let before = Set(FactExtractor.hangingPieces(fen: fenBefore, of: mover).map(\.square))
    if let loose = FactExtractor.hangingPieces(fen: session.position.fen, of: mover).first(where: { !before.contains($0.square) }) {
      return "Careful. Your \(FactExtractor.name(of: loose.kind)) on \(loose.square.notation) can be taken now."
    }
    if facts.motifs.contains(.fork) { return "Lovely fork. Two targets, one move." }
    if facts.motifs.contains(.winsMaterial) { return "Good. That wins material." }
    if facts.motifs.contains(.pin) || facts.motifs.contains(.skewer) { return "Nice. That piece is stuck now." }
    return nil
  }

  /// A nudge for your turn after the opponent's move. `best` is the engine's best for you now;
  /// `turn` rotates the occasional general advice.
  public static func prompt(fenBeforeOpponent: String, opponentMove: String, fenNow: String, best: String?, turn: Int) -> String? {
    guard let me = Position(fen: fenNow)?.sideToMove else { return nil }
    let bestFacts = best.flatMap { FactExtractor.moveFacts(fen: fenNow, uci: $0) }
    let theirs = FactExtractor.moveFacts(fen: fenBeforeOpponent, uci: opponentMove)
    if bestFacts?.motifs.contains(.mate) == true { return "There's a checkmate here. Look at every check." }
    if theirs?.motifs.contains(.mateThreat) == true { return "Careful. They're threatening mate." }
    if let best, let target = FactExtractor.hangingPieces(fen: fenNow, of: me.opposite).first(where: { String(best.dropFirst(2).prefix(2)) == $0.square.notation }) {
      return "Their \(FactExtractor.name(of: target.kind)) looks loose. Can you win it?"
    }
    if bestFacts?.motifs.contains(.fork) == true { return "I smell a fork. Which piece could hit two targets at once?" }
    if bestFacts.map({ $0.motifs.contains(.pin) || $0.motifs.contains(.skewer) }) == true {
      return "Look along the lines. Is there a pin or a skewer?"
    }
    if bestFacts?.motifs.contains(.discoveredAttack) == true { return "What happens if you move a piece out of the way?" }
    if let mine = FactExtractor.hangingPieces(fen: fenNow, of: me).first {
      return "Your \(FactExtractor.name(of: mine.kind)) on \(mine.square.notation) is under attack."
    }
    guard turn > 0, turn.isMultiple(of: 5) else { return nil }
    return advice[(turn / 5) % advice.count]
  }

  static let advice = [
    "Before you move, ask what their last move wants.",
    "Checks, captures, threats. Look at them in that order.",
    "Which of your pieces is doing the least? Give it a job.",
    "No hurry. A good position rewards patience.",
  ]

  static func article(_ motif: Motif) -> String {
    switch motif {
    case .winsMaterial: "winning material"
    case .discoveredAttack: "a discovered attack"
    default: "a " + motif.displayName.lowercased()
    }
  }

  // MARK: - Pre-recorded speech

  /// What the coach says aloud for a line. Same words, minus move names (those stay on screen),
  /// so every spoken line can ship pre-recorded in the coach's voice.
  public static func spoken(_ line: String) -> String {
    if line.hasPrefix("Ah. You had checkmate there") { return "Ah. You had checkmate there." }
    let missed = "Hmm. You missed something. "
    if line.hasPrefix(missed), let was = line.range(of: " was ") {
      let what = line[was.upperBound...].dropLast()  // "a fork"
      return missed + (what == "winning material" ? "You could have won material there." : "You had \(what) there.")
    }
    return line
  }

  /// Bundled audio file name (without extension) for a spoken line.
  public static func clipName(_ spoken: String) -> String {
    spoken.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.joined(separator: "-")
  }

  /// Sample line for Settings → "Hear the coach".
  public static let sample = advice[1]

  /// Every line `spoken(_:)` can produce from `react` and `prompt`: the render script records these.
  public static var allSpokenLines: [String] {
    var lines = advice + [
      "Checkmate. Beautifully done.", "Ah. You had checkmate there.",
      "Lovely fork. Two targets, one move.", "Good. That wins material.", "Nice. That piece is stuck now.",
      "There's a checkmate here. Look at every check.", "Careful. They're threatening mate.",
      "I smell a fork. Which piece could hit two targets at once?", "Look along the lines. Is there a pin or a skewer?",
      "What happens if you move a piece out of the way?",
    ]
    lines += tactics.filter { $0 != .mate }.map { spoken("Hmm. You missed something. X was \(article($0)).") }
    let kinds: [Piece.Kind] = [.pawn, .knight, .bishop, .rook, .queen]
    for kind in kinds {
      let name = FactExtractor.name(of: kind)
      lines.append("Their \(name) looks loose. Can you win it?")
      for file in "abcdefgh" {
        for rank in 1...8 where kind != .pawn || (2...7).contains(rank) {
          lines.append("Careful. Your \(name) on \(file)\(rank) can be taken now.")
          lines.append("Your \(name) on \(file)\(rank) is under attack.")
        }
      }
    }
    return lines
  }
}
