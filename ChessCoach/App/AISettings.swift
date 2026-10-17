import ChessCoachKit
import Foundation
import Observation
import Security

/// API keys, one Keychain item per provider (never typed for the owner: the home PC fills Claude's).
enum KeyStore {
  /// Claude keeps the original service name so keys saved by older builds still load.
  private static func service(_ p: LLMProvider) -> String {
    p == .anthropic ? "com.rishizamvar.chesscoach.anthropic" : "com.rishizamvar.chesscoach.llm.\(p.rawValue)"
  }

  static func read(_ p: LLMProvider) -> String? { read(service: service(p)) }
  @discardableResult
  static func save(_ key: String, for p: LLMProvider) -> Bool { save(key, service: service(p)) }

  /// Any other small secret by name (same protections as the API keys).
  static func read(named name: String) -> String? { read(service: "com.rishizamvar.chesscoach.\(name)") }
  @discardableResult
  static func save(_ value: String, named name: String) -> Bool { save(value, service: "com.rishizamvar.chesscoach.\(name)") }

  private static func read(service: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Updates in place (falls back to add); empty deletes. Returns false if the Keychain refused.
  @discardableResult
  private static func save(_ key: String, service: String) -> Bool {
    let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    if key.isEmpty { return [errSecSuccess, errSecItemNotFound].contains(SecItemDelete(base as CFDictionary)) }
    let attributes: [String: Any] = [
      kSecValueData as String: Data(key.utf8),
      // Never leaves this phone (not in backups or iCloud Keychain).
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return true }
    guard status == errSecItemNotFound else { return false }
    return SecItemAdd(base.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
  }
}

/// Which LLM the coach uses. Provider/models/base URL in UserDefaults, keys in the Keychain.
@MainActor
@Observable
final class AISettings {
  private let defaults = UserDefaults.standard
  /// Bumped on every change so views re-read Keychain-backed state.
  private(set) var revision = 0

  var provider: LLMProvider {
    get { _ = revision; return LLMProvider(rawValue: defaults.string(forKey: "llm.provider") ?? "") ?? .anthropic }
    set { defaults.set(newValue.rawValue, forKey: "llm.provider"); revision += 1 }
  }

  func key(_ p: LLMProvider) -> String { _ = revision; return KeyStore.read(p) ?? "" }
  func setKey(_ key: String, for p: LLMProvider) {
    KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: p)
    revision += 1
  }

  /// Model override for a tier, or "" for the provider default.
  func model(_ tier: LLMTier, _ p: LLMProvider) -> String { _ = revision; return defaults.string(forKey: "llm.\(p.rawValue).\(tier.rawValue)") ?? "" }
  func setModel(_ name: String, _ tier: LLMTier, _ p: LLMProvider) {
    defaults.set(name.trimmingCharacters(in: .whitespaces), forKey: "llm.\(p.rawValue).\(tier.rawValue)")
    revision += 1
  }

  func baseURL(_ p: LLMProvider) -> String { _ = revision; return defaults.string(forKey: "llm.\(p.rawValue).baseURL") ?? "" }
  func setBaseURL(_ url: String, _ p: LLMProvider) {
    defaults.set(url.trimmingCharacters(in: .whitespaces), forKey: "llm.\(p.rawValue).baseURL")
    revision += 1
  }

  /// Call after the home PC drops a key in, so views refresh.
  func keysChanged() { revision += 1 }

  var hasKey: Bool { _ = revision; return Self.config() != nil }

  /// The config the client uses on every call (read fresh, any thread).
  nonisolated static func config() -> LLMConfig? {
    let d = UserDefaults.standard
    let p = LLMProvider(rawValue: d.string(forKey: "llm.provider") ?? "") ?? .anthropic
    let key = KeyStore.read(p)
    guard !p.needsKey || !(key ?? "").isEmpty else { return nil }
    func opt(_ k: String) -> String? { d.string(forKey: "llm.\(p.rawValue).\(k)").flatMap { $0.isEmpty ? nil : $0 } }
    return LLMConfig(
      provider: p, apiKey: key, baseURL: opt("baseURL").flatMap(URL.init(string:)), fastModel: opt("fast"), smartModel: opt("smart"))
  }
}

/// Sign in with Apple, kept on this phone only: nothing about the account leaves the device.
/// Your chess.com username is what the app actually keys your data to.
enum AppleAccount {
  /// Kept in the Keychain (this device only), not in plain preferences.
  static var userID: String? {
    get {
      if let legacy = UserDefaults.standard.string(forKey: "apple.userID") {  // move from older builds
        KeyStore.save(legacy, named: "apple.userID")
        UserDefaults.standard.removeObject(forKey: "apple.userID")
      }
      return KeyStore.read(named: "apple.userID")
    }
    set { KeyStore.save(newValue ?? "", named: "apple.userID") }
  }
}
