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
  /// Base URL of the host that answered last.
  private(set) var baseURL: URL?
  var isOnline: Bool { if case .online = status { true } else { false } }
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
        baseURL = base
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
      baseURL = nil
      lastChecked = Date()
    }
  }

  // MARK: - Deep analysis (chesscoach-server /analysis/jobs)

  struct DeepPosition {
    var fen: String
    var lines: [EngineLine]
  }

  /// Submits a deep-analysis job and polls until done. Returns engine lines per position.
  func deepAnalysis(gameID: String, pgn: String, userColor: String, progress: @escaping (Int, Int) -> Void) async throws -> [DeepPosition] {
    guard let base = baseURL else { throw URLError(.notConnectedToInternet) }
    let jobID = UUID().uuidString
    var request = URLRequest(url: base.appendingPathComponent("analysis/jobs"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(JSON.object([
      "job_id": .string(jobID), "game_id": .string(gameID), "pgn": .string(pgn), "user_color": .string(userColor),
      "depth": .number(22), "multipv": .number(3),
    ]))
    request.timeoutInterval = 10
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { throw URLError(.badServerResponse) }
    let statusURL = base.appendingPathComponent("analysis/jobs/\(jobID)")
    for _ in 0..<600 {
      try await Task.sleep(for: .seconds(2))
      let (data, _) = try await URLSession.shared.data(from: statusURL)
      let job = try JSONDecoder().decode(JSON.self, from: data)
      if let done = job["progress"]?["done"]?.numberValue, let total = job["progress"]?["total"]?.numberValue {
        progress(Int(done), Int(total))
      }
      switch job["status"]?.stringValue {
      case "done": return Self.parsePositions(job["result"])
      case "failed": throw URLError(.badServerResponse)
      default: continue
      }
    }
    throw URLError(.timedOut)
  }

  /// `result.positions = [{fen, lines: [{multipv, depth, cp|mate, pv}]}]` (plan M5).
  nonisolated static func parsePositions(_ result: JSON?) -> [DeepPosition] {
    (result?["positions"]?.arrayValue ?? []).compactMap { p in
      guard let fen = p["fen"]?.stringValue else { return nil }
      let lines: [EngineLine] = (p["lines"]?.arrayValue ?? []).compactMap { l in
        let pv = (l["pv"]?.arrayValue ?? []).compactMap(\.stringValue)
        guard !pv.isEmpty else { return nil }
        let score: EngineScore =
          if let mate = l["mate"]?.numberValue { .mate(Int(mate)) } else { .centipawns(Int(l["cp"]?.numberValue ?? 0)) }
        return EngineLine(multipv: Int(l["multipv"]?.numberValue ?? 1), depth: Int(l["depth"]?.numberValue ?? 0), score: score, pv: pv)
      }
      return lines.isEmpty ? nil : DeepPosition(fen: fen, lines: lines)
    }
  }

  private func getJSON(_ url: URL) async throws -> JSON {
    let (data, response) = try await session.data(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(JSON.self, from: data)
  }
}
