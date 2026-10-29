import ChessCoachKit
import CryptoKit
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
    // Experiment (spec W7): the first-launch puzzle mode comes from the coach_mode_default flag.
    if UserDefaults.standard.string(forKey: PuzzleMode.key) == nil {
      PostHogSDK.shared.reloadFeatureFlags {
        guard UserDefaults.standard.string(forKey: PuzzleMode.key) == nil else { return }
        let coach = PostHogSDK.shared.isFeatureEnabled("coach_mode_default")
        UserDefaults.standard.set((coach ? PuzzleMode.coach : .instant).rawValue, forKey: PuzzleMode.key)
      }
    }
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

extension AnalyticsSetup {
  static let richAskedKey = "analytics.richAsked"
  static let installIDKey = "analytics.installID"
  static let privacyURL = URL(string: "https://chess.zamvar.io/privacy")!

  /// The identified tier's ID: a hash of your Apple user ID (or a random install ID), never the raw ID.
  static var userID: String {
    let raw = AppleAccount.userID ?? {
      if let id = UserDefaults.standard.string(forKey: installIDKey) { return id }
      let id = UUID().uuidString
      UserDefaults.standard.set(id, forKey: installIDKey)
      return id
    }()
    return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
  }

  /// PostHog's ID for this device (for delete requests); nil when analytics isn't configured.
  @MainActor static var distinctID: String? { apiKey == nil ? nil : PostHogSDK.shared.getDistinctId() }

  /// Should we ask about the training profile? Once, after onboarding, only when analytics is configured.
  static var shouldAskRich: Bool { apiKey != nil && !UserDefaults.standard.bool(forKey: richAskedKey) }
}

extension TrainingService {
  /// Person properties for the opt-in training profile (spec W7 rich tier).
  func analyticsProfile(_ env: AppEnvironment) -> [String: JSONValue] {
    var p: [String: JSONValue] = [
      "puzzle_rating": .int(globalRating), "style": .string(profile?.style.rawValue ?? "unknown"),
      "ai_provider": .string(env.aiSettings.provider.rawValue), "locale": .string(Locale.current.identifier),
      "lessons_passed": .int(lessonProgress.values.filter(\.passed).count),
    ]
    if let name = profile?.username, !name.isEmpty { p["chesscom_username"] = .string(name) }
    if let real = realRating { p["chesscom_rating"] = .int(real) }
    for (id, r) in skillRatings where id != TrainingStore.globalSkill { p["skill_\(id)"] = .int(Int(r.rating)) }
    return p
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
