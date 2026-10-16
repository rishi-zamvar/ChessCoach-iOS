import ChessCoachKit
import Foundation
import Observation
import Security

/// The Anthropic key, stored only in the Keychain (never typed by the user).
enum KeyStore {
  private static let service = "com.rishizamvar.chesscoach.anthropic"

  static func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ key: String) {
    let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = Data(key.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }
}

/// Finds the home PC over Tailscale and pulls the API key from it (the PC checks who's
/// asking with `tailscale whois`, so the phone holds no secret of its own).
@MainActor
@Observable
final class ServerLink {
  enum Status: Equatable {
    case unknown, checking, online(version: String), offline
  }

  private(set) var status: Status = .unknown
  private(set) var keyID: String? = UserDefaults.standard.string(forKey: "ai.keyID")
  private(set) var lastChecked: Date?
  var hasKey: Bool { KeyStore.read() != nil }

  /// MagicDNS name first, then the PC's Tailscale IP.
  static let hosts = ["zee-cloud", "100.91.236.115"]
  static let port = 8810

  @ObservationIgnored private let telemetry: Telemetry
  @ObservationIgnored private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 1.5
    config.timeoutIntervalForResource = 4
    return URLSession(configuration: config)
  }()

  init(telemetry: Telemetry) {
    self.telemetry = telemetry
  }

  /// Health check + key refresh. Cheap; call on launch and when the app comes forward.
  func refresh() async {
    guard status != .checking else { return }
    status = .checking
    await telemetry.step("server.link") { ctx in
      for host in Self.hosts {
        guard let base = URL(string: "http://\(host):\(Self.port)") else { continue }
        guard let health = try? await getJSON(base.appendingPathComponent("health")), health["ok"] == .bool(true) else { continue }
        status = .online(version: health["version"]?.stringValue ?? "?")
        ctx.annotate("host", .string(host))
        if let key = try? await getJSON(base.appendingPathComponent("key")), let secret = key["key"]?.stringValue {
          let id = key["key_id"]?.stringValue ?? String(secret.suffix(6))
          if id != keyID || !hasKey {
            KeyStore.save(secret)
            keyID = id
            UserDefaults.standard.set(id, forKey: "ai.keyID")
            telemetry.event("key.handoff", metadata: ["key_id": .string(id)])
          }
        }
        lastChecked = Date()
        return
      }
      status = .offline
      lastChecked = Date()
    }
  }

  private func getJSON(_ url: URL) async throws -> JSON {
    let (data, response) = try await session.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(JSON.self, from: data)
  }
}
