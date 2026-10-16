import Foundation

/// Turns a fact sheet into 1–2 plain sentences without any AI. Every move or
/// square it names comes from the sheet (checked by `Explainer.mentions`).
public enum Explainer {
  /// - parameter isUser: whether the mover is the user ("your" vs "their").
  public static func explain(_ sheet: FactSheet, as label: MoveClass, isUser: Bool) -> String {
    let own = isUser ? "your" : "their"
    let other = isUser ? "they" : "you"
    switch label {
    case .book:
      return "\(sheet.played.san) is a known opening move."
    case .forced:
      return "\(sheet.played.san) was the only legal move."
    case .brilliant:
      return "\(sheet.played.san)! A sound sacrifice that few players at this level would find."
    case .great:
      return "\(sheet.played.san) is the only move that keeps the advantage — everything else lets it slip."
    case .best, .excellent, .good:
      return positive(sheet, label: label)
    case .inaccuracy, .mistake, .blunder, .miss:
      return error(sheet, label: label, own: own, other: other)
    }
  }

  // MARK: - Good moves

  static func positive(_ sheet: FactSheet, label: MoveClass) -> String {
    let san = sheet.played.san
    let motifs = sheet.played.motifs
    if motifs.contains(.mate) { return "\(san) is checkmate." }
    if motifs.contains(.fork), !sheet.played.targets.isEmpty {
      return "\(san) forks the \(list(sheet.played.targets)) — one of them will fall."
    }
    if motifs.contains(.winsMaterial) { return "\(san) wins material." }
    if motifs.contains(.pin) { return "\(san) pins a piece in place." }
    if motifs.contains(.mateThreat) { return "\(san) threatens mate." }
    switch label {
    case .best: return "\(san) is the engine's top choice."
    case .excellent: return "\(san) is an excellent move, almost as good as the best."
    default:
      if let best = sheet.best { return "\(san) is fine. \(best.san) was a little more precise." }
      return "\(san) is a solid move."
    }
  }

  // MARK: - Errors

  static func error(_ sheet: FactSheet, label: MoveClass, own: String, other: String) -> String {
    let san = sheet.played.san
    var reason: String
    if let punish = sheet.punish, punish.motifs.contains(.mate) {
      reason = "\(san) allows \(punish.san), checkmate."
    } else if let punish = sheet.punish, punish.motifs.contains(.fork), !punish.targets.isEmpty {
      reason = "\(san) allows \(punish.san), forking \(own) \(list(punish.targets))."
    } else if let hanging = sheet.hangingAfter.first, let punish = sheet.punish, punish.materialWon >= 2 || punish.uci.hasSuffix(hanging.square) {
      reason = "\(san) leaves \(own) \(hanging.kind) on \(hanging.square) unprotected — \(punish.san) wins it."
    } else if let hanging = sheet.hangingAfter.first {
      reason = "After \(san), \(own) \(hanging.kind) on \(hanging.square) can be taken."
    } else if let punish = sheet.punish, punish.motifs.contains(.mateThreat) {
      reason = "\(san) lets \(other) threaten mate with \(punish.san)."
    } else if let punish = sheet.punish, let motif = punish.motifs.first(where: { [.pin, .skewer, .discoveredAttack, .winsMaterial].contains($0) }) {
      reason = "\(san) allows \(punish.san) — a \(motif.displayName.lowercased())."
    } else if label == .miss {
      reason = "Your opponent's last move gave you a chance, but \(san) let it go."
    } else if let best = sheet.best, best.motifs.contains(where: { [.mate, .fork, .winsMaterial, .pin, .skewer, .discoveredAttack].contains($0) }) {
      reason = "\(san) misses a tactic."
    } else {
      reason = "\(san) weakens \(own) position."
    }

    if let best = sheet.best {
      reason += " " + better(best, line: sheet.bestLineSAN)
    }
    return reason
  }

  static func better(_ best: MoveFacts, line: [String]) -> String {
    if best.motifs.contains(.mate) { return "\(best.san) was checkmate!" }
    if best.motifs.contains(.fork), !best.targets.isEmpty { return "Better was \(best.san), forking the \(list(best.targets))." }
    if best.motifs.contains(.winsMaterial) { return "Better was \(best.san), winning material." }
    if best.motifs.contains(.mateThreat) { return "Better was \(best.san), threatening mate." }
    if line.count >= 3 { return "Better was \(best.san) (\(line.prefix(3).joined(separator: " ")))." }
    return "Better was \(best.san)."
  }

  static func list(_ pieces: [PieceFact]) -> String {
    let names = pieces.map { "\($0.kind) on \($0.square)" }
    switch names.count {
    case 0: return ""
    case 1: return names[0]
    default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
  }

  // MARK: - Validation

  /// SAN moves and squares mentioned in `text` (used to check generated text,
  /// template or AI, against a fact sheet's vocabulary).
  public static func mentions(in text: String) -> Set<String> {
    let pattern = #"(O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](=[QRBN])?[+#]?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var result = Set<String>()
    for match in regex.matches(in: text, range: range) {
      guard let r = Range(match.range, in: text) else { continue }
      let token = String(text[r])
      // Pure squares match too ("e4"); trailing punctuation is part of SAN.
      result.insert(token)
    }
    return result
  }

  /// True when every move/square mentioned in `text` appears in the sheet.
  public static func isGrounded(_ text: String, in sheet: FactSheet) -> Bool {
    let vocabulary = sheet.vocabulary
    let squares = Set(vocabulary.flatMap { token in mentions(in: token).compactMap { squareSuffix($0) } })
    return mentions(in: text).allSatisfy { token in
      vocabulary.contains(token) || squares.contains(token)
        || squareSuffix(token).map { squares.contains($0) && token.count == 2 } == true
    }
  }

  static func squareSuffix(_ token: String) -> String? {
    let stripped = token.replacingOccurrences(of: #"[+#]|=[QRBN]"#, with: "", options: .regularExpression)
    guard stripped.count >= 2 else { return nil }
    return String(stripped.suffix(2))
  }
}
