import ChessCoachKit
import Foundation
import Observation
import CryptoKit
import Security

/// Background link to the home PC over Tailscale: pulls the Claude key from it (the PC checks who's
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
  /// The PC handed this phone its key (owner on the tailnet).
  var deliveredKey: Bool { keyID != nil && KeyStore.read(.anthropic) != nil }

  /// The PC's MagicDNS name: iOS only allows plain HTTP (NSAllowsLocalNetworking) to bare
  /// hostnames, not to 100.x IPs. A hostile Wi-Fi DNS could answer the name, so it is only
  /// used when every address it resolves to is the PC's Tailscale IP or a tailnet IPv6.
  static let host = "zee-cloud"
  nonisolated static let pinnedIPv4 = "100.91.236.115"
  static let port = 8810

  /// True when `addresses` is non-empty and each is the pinned IPv4 or inside Tailscale's fd7a:115c:a1e0::/48.
  nonisolated static func isTailnet(_ addresses: [String]) -> Bool {
    !addresses.isEmpty && addresses.allSatisfy { $0 == pinnedIPv4 || $0.lowercased().hasPrefix("fd7a:115c:a1e0:") }
  }

  /// Every address `host` resolves to (blocking getaddrinfo, so run off the main actor).
  nonisolated static func resolve(_ host: String) async -> [String] {
    await Task.detached {
      var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
        ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
      var list: UnsafeMutablePointer<addrinfo>?
      guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
      defer { freeaddrinfo(list) }
      var out: [String] = []
      for info in sequence(first: first, next: { $0.pointee.ai_next }) {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
          out.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).components(separatedBy: "%")[0])
        }
      }
      return out
    }.value
  }

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
      for host in [Self.host] {
        let addresses = await Self.resolve(host)
        guard Self.isTailnet(addresses) else {
          ctx.annotate("rejected", .string(addresses.joined(separator: ",")))
          continue
        }
        guard let base = URL(string: "http://\(host):\(Self.port)") else { continue }
        guard let health = try? await getJSON(base.appendingPathComponent("health")), health["ok"] == .bool(true) else { continue }
        status = .online(version: health["version"]?.stringValue ?? "?")
        baseURL = base
        ctx.annotate("host", .string(host))
        if let key = try? await getJSON(base.appendingPathComponent("key")), let secret = key["key"]?.stringValue,
          secret.hasPrefix("sk-ant-"), secret.count > 30
        {
          let id = Self.keyID(secret)
          if id != keyID || KeyStore.read(.anthropic) == nil {
            let saved = KeyStore.save(secret, for: .anthropic)
            if saved {
              keyID = id
              UserDefaults.standard.set(id, forKey: "ai.keyID")
            }
            telemetry.event("key.handoff", metadata: ["key_id": .string(id), "saved": .bool(saved)])
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

  /// First 8 hex digits of SHA-256(key) — identifies the key without revealing any of it.
  static func keyID(_ key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Account (Sign in with Apple, once at onboarding)

  /// Trades Apple's identity token (a JWT) for this server's session JWT. Returns the chess.com
  /// username already linked to this Apple ID (a reinstall or a new phone), if any.
  /// False when the PC isn't reachable: the phone stays signed in to Apple only.
  func signIn(appleIdentityToken: String) async -> (ok: Bool, username: String?) {
    if baseURL == nil { await refresh() }
    guard let base = baseURL,
      let reply = try? await sendJSON("POST", base.appendingPathComponent("auth/apple"), ["identity_token": .string(appleIdentityToken)]),
      let token = reply["token"]?.stringValue
    else { return (false, nil) }
    KeyStore.session = token
    telemetry.event("auth.apple", metadata: ["linked": .bool(reply["chesscom_username"]?.stringValue != nil)])
    return (true, reply["chesscom_username"]?.stringValue)
  }

  /// Links the chess.com username to the signed-in Apple ID.
  func linkChessCom(_ username: String) async {
    guard let base = baseURL, let token = KeyStore.session else { return }
    _ = try? await sendJSON("PUT", base.appendingPathComponent("account"), ["chesscom_username": .string(username)], bearer: token)
  }

  private func sendJSON(_ method: String, _ url: URL, _ body: [String: JSON], bearer: String? = nil) async throws -> JSON {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
    request.httpBody = try JSONEncoder().encode(JSON.object(body))
    // Apple's keys may need fetching on the PC: allow longer than a health check.
    request.timeoutInterval = 8
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(JSON.self, from: data)
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
