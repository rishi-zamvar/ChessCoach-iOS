import CryptoKit
import DeviceCheck
import Foundation

/// The internet-facing ChessCoach server (the home PC behind a Cloudflare Tunnel): deep analysis
/// for people who aren't on the owner's Tailscale. Every request is signed with an App Attest key,
/// so the server only serves genuine installs of this app.
@MainActor
final class PublicServer {
  static let shared = PublicServer()

  /// From Info.plist (`PublicServerURL`); empty until the tunnel's domain exists.
  let baseURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "PublicServerURL") as? String)
    .flatMap { $0.isEmpty ? nil : URL(string: $0) }

  /// App Attest needs a real device (not the simulator) and a configured server.
  var isAvailable: Bool { baseURL != nil && DCAppAttestService.shared.isSupported }

  private let keyIDKey = "appattest.keyID"
  private let registeredKey = "appattest.registered"
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    return URLSession(configuration: config)
  }()

  /// What the server checks the assertion against: method, path and the exact body bytes.
  nonisolated static func clientData(method: String, path: String, body: Data) -> Data {
    Data("\(method)\n\(path)\n".utf8) + body
  }

  /// Sends a signed request; returns the response body (throws on non-2xx).
  func send(_ method: String, _ path: String, body: Data = Data()) async throws -> Data {
    guard let baseURL else { throw URLError(.unsupportedURL) }
    let keyID = try await attestedKey()
    let hash = Data(SHA256.hash(data: Self.clientData(method: method, path: path, body: body)))
    let assertion: Data
    do {
      assertion = try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: hash)
    } catch {
      reset()  // the key was lost (e.g. restored backup): attest a fresh one next time
      throw error
    }
    var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
    request.httpMethod = method
    request.httpBody = method == "GET" ? nil : body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(keyID, forHTTPHeaderField: "X-Attest-Key")  // already base64 of SHA256(public key)
    request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Attest-Assertion")
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401 { reset() }
    guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
    return data
  }

  /// The App Attest key id, generating and registering it with the server the first time.
  private func attestedKey() async throws -> String {
    let defaults = UserDefaults.standard
    if let keyID = defaults.string(forKey: keyIDKey), defaults.bool(forKey: registeredKey) { return keyID }
    let service = DCAppAttestService.shared
    let keyID = try await service.generateKey()
    let challenge = try await post("/v1/attest/challenge", [:])["challenge"].flatMap { Data(base64Encoded: $0) }
    guard let challenge else { throw URLError(.badServerResponse) }
    let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: challenge)))
    _ = try await post("/v1/attest/register", [
      "key_id": keyID, "attestation": attestation.base64EncodedString(), "challenge": challenge.base64EncodedString(),
    ])
    defaults.set(keyID, forKey: keyIDKey)
    defaults.set(true, forKey: registeredKey)
    return keyID
  }

  private func post(_ path: String, _ json: [String: String]) async throws -> [String: String] {
    guard let baseURL else { throw URLError(.unsupportedURL) }
    var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: json)
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
  }

  private func reset() {
    UserDefaults.standard.removeObject(forKey: keyIDKey)
    UserDefaults.standard.removeObject(forKey: registeredKey)
  }
}
