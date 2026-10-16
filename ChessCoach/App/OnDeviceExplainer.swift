import ChessCoachKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// M7: Apple's on-device model (iOS 26+, Apple Intelligence devices) rewrites
/// explanations when Claude isn't available. Same facts, same grounding check.
enum OnDeviceExplainer {
  static var isAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
    #endif
    return false
  }

  static func explain(sheet: FactSheet, label: MoveClass, isUser: Bool, template: String) async -> String? {
    #if canImport(FoundationModels)
    guard #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable else { return nil }
    let session = LanguageModelSession(instructions: AIExplainer.system)
    let prompt = "FACTS:\n\(AIExplainer.factsBlock(sheet: sheet, label: label, isUser: isUser, template: template))\n\nRewrite the explanation for this \(label.displayName.lowercased()) move."
    guard let response = try? await session.respond(to: prompt) else { return nil }
    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    return !text.isEmpty && Explainer.isGrounded(text, in: sheet) ? text : nil
    #else
    return nil
    #endif
  }
}
