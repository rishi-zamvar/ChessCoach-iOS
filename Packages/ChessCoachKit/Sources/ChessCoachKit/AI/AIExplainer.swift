import Foundation

/// Rewrites a template explanation in natural coach language (Haiku), grounded in the
/// fact sheet. Any move or square not in the facts → one corrective retry → template.
public struct AIExplainer: Sendable {
  public enum Origin: String, Sendable { case ai, template, cache }

  let client: AnthropicClient
  let store: AIStore?
  let model: String

  public init(client: AnthropicClient, store: AIStore?, model: String = AnthropicClient.explainModel) {
    self.client = client
    self.store = store
    self.model = model
  }

  static let system = """
    You are a warm, concise chess coach talking to a beginner (about 300–600 rated) in a phone app.
    Rewrite the given explanation of one chess move in 1–2 short sentences of plain English, second person ("you", "your").
    Rules:
    - Use ONLY the facts provided. Every move (in SAN) or square you mention must appear in the FACTS block. Never invent moves, squares or lines.
    - Say what happened and why it matters; teach the habit when natural (e.g. "check what your opponent's move attacks").
    - No markdown, no lists, no emojis, no headings. Don't mention engines, evaluations or numbers.
    - Output only the explanation text.
    """

  public func explain(sheet: FactSheet, label: MoveClass, isUser: Bool, template: String, styleNote: String = "") async -> (text: String, origin: Origin) {
    let key = "\(model)|\(sheet.played.uci)|\(label.rawValue)|\(isUser)|\(template)"
    if let cached = store?.cachedExplanation(key: key) { return (cached, .cache) }
    guard client.isAvailable else { return (template, .template) }

    let facts = Self.factsBlock(sheet: sheet, label: label, isUser: isUser, template: template)
    var prompt = "FACTS:\n\(facts)\n\nRewrite the explanation for this \(label.displayName.lowercased()) move."
    if !styleNote.isEmpty { prompt += " The learner's style: \(styleNote)." }
    for attempt in 0..<2 {
      guard
        let turn = try? await client.send(
          model: model, system: Self.system, messages: [.object(["role": .string("user"), "content": .string(prompt)])],
          maxTokens: 300, purpose: "explain")
      else { return (template, .template) }
      let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !text.isEmpty, Explainer.isGrounded(text, in: sheet) {
        store?.cacheExplanation(key: key, text: text, model: model)
        return (text, .ai)
      }
      let stray = Explainer.mentions(in: text).subtracting(sheet.vocabulary).sorted().joined(separator: ", ")
      prompt += "\n\nYour previous answer mentioned \(stray), which is not in the FACTS. Rewrite using only moves and squares from the FACTS."
      _ = attempt
    }
    return (template, .template)
  }

  static func factsBlock(sheet: FactSheet, label: MoveClass, isUser: Bool, template: String) -> String {
    var lines: [String] = []
    lines.append("Mover: \(isUser ? "the learner" : "the opponent") (\(sheet.mover))")
    lines.append("Move played: \(sheet.played.san) — classified \(label.displayName)")
    if !sheet.played.motifs.isEmpty { lines.append("Played move themes: \(sheet.played.motifs.map(\.displayName).joined(separator: ", "))") }
    if let best = sheet.best {
      lines.append("Better move: \(best.san)\(best.motifs.isEmpty ? "" : " (\(best.motifs.map(\.displayName).joined(separator: ", ")))")")
    }
    if !sheet.bestLineSAN.isEmpty { lines.append("Better line: \(sheet.bestLineSAN.prefix(4).joined(separator: " "))") }
    if let punish = sheet.punish {
      lines.append("Opponent's best reply: \(punish.san)\(punish.motifs.isEmpty ? "" : " (\(punish.motifs.map(\.displayName).joined(separator: ", ")))")")
    }
    if !sheet.punishLineSAN.isEmpty { lines.append("Punishing line: \(sheet.punishLineSAN.prefix(4).joined(separator: " "))") }
    for h in sheet.hangingAfter { lines.append("Left unprotected after the move: \(h.kind) on \(h.square)") }
    for t in (sheet.best?.targets ?? []) + (sheet.punish?.targets ?? []) { lines.append("Target: \(t.kind) on \(t.square)") }
    lines.append("Phase: \(sheet.phase.rawValue)")
    lines.append("Template explanation: \(template)")
    return lines.joined(separator: "\n")
  }
}
