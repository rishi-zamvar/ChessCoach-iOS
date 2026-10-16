import Foundation

/// A raw HTTP response. Header names are stored lowercased.
public struct HTTPResponse: Sendable, Equatable {
  public var status: Int
  public var headers: [String: String]
  public var body: Data

  public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.status = status
    self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
    self.body = body
  }
}

/// Minimal GET-only transport so the chess.com client can be tested with scripted responses.
public protocol HTTPClient: Sendable {
  func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

/// `URLSession`-backed client. Local caching is bypassed so a 304 reaches the caller.
public struct URLSessionHTTPClient: HTTPClient {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    var out: [String: String] = [:]
    for (k, v) in http.allHeaderFields {
      if let k = k as? String { out[k] = "\(v)" }
    }
    return HTTPResponse(status: http.statusCode, headers: out, body: data)
  }
}
