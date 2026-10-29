import Foundation

/// What the user agreed to share (Settings → Privacy). Basic = anonymous usage; rich = identified profile (M3).
public enum AnalyticsConsent: String, Sendable {
  case off, basic, rich
}

/// A product-analytics backend (PostHog in the app; a fake in tests).
public protocol AnalyticsClient: Sendable {
  func capture(_ name: String, properties: [String: JSONValue])
  func identify(_ id: String, properties: [String: JSONValue])
  func reset()
}

/// Turns telemetry steps into product events (`area.action`, spec W7). Only allow-listed steps
/// leave the phone, and their metadata is scrubbed of anything personal or free-form.
public enum AnalyticsEvent {
  /// Old step name → taxonomy name, plus metadata keys to rename.
  static let renamed: [String: (name: String, keys: [String: String])] = [
    "app.launch": ("app.open", [:]),
    "onboarding.complete": ("onboarding.done", ["rating": "placement_rating"]),
    "onboarding.reset": ("onboarding.reset", [:]),
    "training.plan": ("plan.built", ["items": "blocks"]),
    "training.puzzle": ("puzzle.done", ["solved": "first_move_ok", "seconds": "secs"]),
    "training.review": ("review.graded", [:]),
    "training.lesson": ("lesson.done", [:]),
    "training.drill": ("drill.done", ["seconds": "secs"]),
    "rating.anchor": ("rating.anchor", [:]),
  ]
  /// Steps already named in the taxonomy pass through unchanged.
  static let passthroughAreas: Set<String> = ["screen", "plan", "feedback", "settings", "analysis", "review", "game", "coach", "rush", "puzzle", "lesson"]
  static let sensitiveKeyParts = ["key", "token", "email", "username", "user", "text", "prompt", "pgn", "question", "answer", "name_full"]

  public static func map(_ event: StepEvent) -> (name: String, properties: [String: JSONValue])? {
    switch event.phase {
    case .start, .progress: return nil
    case .fail: return ("error", ["where": .string(event.step)])
    case .finish: break
    }
    let name: String
    var keys: [String: String] = [:]
    if let r = renamed[event.step] {
      (name, keys) = r
    } else if let area = event.step.split(separator: ".").first, passthroughAreas.contains(String(area)), !event.step.hasPrefix("analysis.ply") {
      name = event.step
    } else {
      return nil
    }
    var props: [String: JSONValue] = [:]
    for (key, value) in event.metadata {
      guard let clean = scrub(key: key, value) else { continue }
      props[keys[key] ?? key] = clean
    }
    if let ms = event.durationMs { props["ms"] = .double(ms.rounded()) }
    return (name, props)
  }

  /// Drops personal or free-form values; keeps numbers, flags and short identifiers.
  public static func scrub(key: String, _ value: JSONValue) -> JSONValue? {
    let lower = key.lowercased()
    if sensitiveKeyParts.contains(where: { lower.contains($0) }) && lower != "name" { return nil }
    if case .string(let s) = value, s.count > 64 { return nil }
    return value
  }
}

/// Sends mapped telemetry to the analytics client while the user's consent allows it.
public final class AnalyticsSink: TelemetrySink, @unchecked Sendable {
  private let client: AnalyticsClient
  private let consent: @Sendable () -> AnalyticsConsent

  public init(client: AnalyticsClient, consent: @escaping @Sendable () -> AnalyticsConsent) {
    self.client = client
    self.consent = consent
  }

  public func record(_ event: StepEvent) {
    guard consent() != .off, let mapped = AnalyticsEvent.map(event) else { return }
    client.capture(mapped.name, properties: mapped.properties)
  }
}
