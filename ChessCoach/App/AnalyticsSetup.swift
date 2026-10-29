import ChessCoachKit
import Foundation
import PostHog

/// Product analytics (spec W7) through PostHog's EU cloud. Off until `PostHogAPIKey` is set in
/// Info.plist, and always subject to Settings → Privacy.
enum AnalyticsSetup {
  static let consentKey = "analytics.consent"

  /// Basic (anonymous) is on by default; the identified tier is opt-in.
  static var consent: AnalyticsConsent {
    AnalyticsConsent(rawValue: UserDefaults.standard.string(forKey: consentKey) ?? "") ?? .basic
  }

  static var apiKey: String? {
    (Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String).flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Starts the SDK when a key is configured; returns the client the telemetry sink sends to.
  @MainActor static func start(inMemory: Bool) -> AnalyticsClient? {
    guard !inMemory, let apiKey else { return nil }
    let host = Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String ?? "https://eu.i.posthog.com"
    let config = PostHogConfig(apiKey: apiKey, host: host)
    config.captureScreenViews = false  // we send our own screen.view with real screen names
    config.captureApplicationLifecycleEvents = true
    config.personProfiles = .identifiedOnly  // basic tier never creates a person
    config.sessionReplay = consent == .rich
    config.sessionReplayConfig.maskAllTextInputs = true
    config.sessionReplayConfig.screenshotMode = true
    PostHogSDK.shared.setup(config)
    if consent == .off { PostHogSDK.shared.optOut() }
    return PostHogClient()
  }

  /// Settings → Privacy changed.
  @MainActor static func setConsent(_ value: AnalyticsConsent, profile: () -> [String: JSONValue], userID: () -> String) {
    UserDefaults.standard.set(value.rawValue, forKey: consentKey)
    guard apiKey != nil else { return }
    switch value {
    case .off:
      PostHogSDK.shared.reset()
      PostHogSDK.shared.optOut()
    case .basic:
      PostHogSDK.shared.optIn()
      PostHogSDK.shared.reset()  // forget any identified profile on this device
    case .rich:
      PostHogSDK.shared.optIn()
      PostHogClient().identify(userID(), properties: profile())
    }
  }
}

struct PostHogClient: AnalyticsClient {
  func capture(_ name: String, properties: [String: JSONValue]) {
    PostHogSDK.shared.capture(name, properties: properties.mapValues(\.any))
  }

  func identify(_ id: String, properties: [String: JSONValue]) {
    PostHogSDK.shared.identify(id, userProperties: properties.mapValues(\.any))
  }

  func reset() { PostHogSDK.shared.reset() }
}

extension JSONValue {
  var any: Any {
    switch self {
    case .string(let s): s
    case .int(let i): i
    case .double(let d): d
    case .bool(let b): b
    case .null: NSNull()
    }
  }
}
