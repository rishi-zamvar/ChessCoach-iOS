import Foundation

/// Minimal JSON value with objects/arrays (API payloads, tool inputs/results).
public indirect enum JSON: Codable, Equatable, Sendable {
  case string(String), number(Double), bool(Bool), null
  case array([JSON]), object([String: JSON])

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let a = try? c.decode([JSON].self) { self = .array(a) }
    else { self = .object(try c.decode([String: JSON].self)) }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let s): try c.encode(s)
    case .number(let n): try c.encode(n)
    case .bool(let b): try c.encode(b)
    case .null: try c.encodeNil()
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  public subscript(key: String) -> JSON? {
    if case .object(let o) = self { return o[key] }
    return nil
  }

  public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
  public var arrayValue: [JSON]? { if case .array(let a) = self { a } else { nil } }
  public var numberValue: Double? { if case .number(let n) = self { n } else { nil } }

  /// Compact JSON text (tool results).
  public var text: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? "null"
  }
}

/// A client-side tool definition.
public struct AITool: Sendable {
  public var name: String
  public var description: String
  public var inputSchema: JSON

  public init(name: String, description: String, inputSchema: JSON) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }

  var json: JSON {
    .object(["name": .string(name), "description": .string(description), "input_schema": inputSchema, "strict": .bool(true)])
  }
}

/// Transport seam (URLSession in the app, a fake in tests).
public protocol AITransport: Sendable {
  func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, body: Data)
}

public struct URLSessionAITransport: AITransport {
  public init() {}
  public func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.timeoutInterval = 60
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    let (data, response) = try await URLSession.shared.data(for: request)
    return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
  }
}

public enum AIError: Error, Equatable {
  case noKey
  case budgetExceeded(spentUSD: Double)
  case http(status: Int, message: String)
  case refused
  case badResponse
}

/// Token usage and dollar cost of one call.
public struct AIUsage: Codable, Equatable, Sendable {
  public var model: String
  public var inputTokens: Int
  public var outputTokens: Int
  public var cacheReadTokens: Int
  public var cacheWriteTokens: Int

  /// USD per million tokens (input, output) from the published price table.
  static func prices(_ model: String) -> (input: Double, output: Double) {
    if model.hasPrefix("claude-haiku") { return (1, 5) }
    if model.hasPrefix("claude-sonnet") { return (2, 10) }
    if model.hasPrefix("claude-opus") { return (4, 20) }
    return (5, 25)
  }

  public var costUSD: Double {
    let p = Self.prices(model)
    let input = Double(inputTokens) * p.input + Double(cacheWriteTokens) * p.input * 1.25 + Double(cacheReadTokens) * p.input * 0.1
    return (input + Double(outputTokens) * p.output) / 1_000_000
  }
}

/// Spend ledger (the app enforces a monthly cap).
public protocol AISpendLedger: Sendable {
  func spentThisMonth() -> Double
  func record(_ usage: AIUsage, purpose: String, latencyMs: Double)
}

/// Raw-HTTP Messages API client with a client-side tool loop.
public struct AnthropicClient: Sendable {
  public static let explainModel = "claude-haiku-4-5"
  public static let coachModel = "claude-sonnet-5-5"

  let keyProvider: @Sendable () -> String?
  let transport: AITransport
  let telemetry: Telemetry
  let ledger: AISpendLedger?
  let monthlyCapUSD: Double
  let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

  public init(
    keyProvider: @escaping @Sendable () -> String?, transport: AITransport = URLSessionAITransport(),
    telemetry: Telemetry, ledger: AISpendLedger?, monthlyCapUSD: Double = 80
  ) {
    self.keyProvider = keyProvider
    self.transport = transport
    self.telemetry = telemetry
    self.ledger = ledger
    self.monthlyCapUSD = monthlyCapUSD
  }

  /// Calls stop a little before the cap so parallel/looping calls can't overshoot it.
  var effectiveCap: Double { monthlyCapUSD * 0.98 }

  public var isAvailable: Bool { keyProvider() != nil && (ledger?.spentThisMonth() ?? 0) < effectiveCap }

  public struct Turn: Sendable {
    /// Assistant content blocks exactly as returned (echoed back when continuing).
    public var content: [JSON]
    public var stopReason: String
    public var usage: AIUsage
    public var text: String {
      content.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined()
    }
    public var toolUses: [(id: String, name: String, input: JSON)] {
      content.compactMap { block in
        guard block["type"]?.stringValue == "tool_use", let id = block["id"]?.stringValue,
          let name = block["name"]?.stringValue
        else { return nil }
        return (id, name, block["input"] ?? .object([:]))
      }
    }
  }

  /// One Messages API call. `system` is cached (stable prefix).
  public func send(
    model: String, system: String, messages: [JSON], tools: [AITool] = [], maxTokens: Int = 1024,
    effort: String? = nil, purpose: String
  ) async throws -> Turn {
    guard let key = keyProvider() else { throw AIError.noKey }
    let spent = ledger?.spentThisMonth() ?? 0
    guard spent < effectiveCap else { throw AIError.budgetExceeded(spentUSD: spent) }

    var body: [String: JSON] = [
      "model": .string(model),
      "max_tokens": .number(Double(maxTokens)),
      "system": .array([.object(["type": .string("text"), "text": .string(system), "cache_control": .object(["type": .string("ephemeral")])])]),
      "messages": .array(messages),
    ]
    if !tools.isEmpty { body["tools"] = .array(tools.map(\.json)) }
    if let effort { body["output_config"] = .object(["effort": .string(effort)]) }
    var headers = ["content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01"]
    if model.hasPrefix("claude-sonnet-5-5") {
      // Server-side refusal fallback (Claude API, Sonnet 5.5: "default" form only).
      body["fallbacks"] = .string("default")
      headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
    }
    let data = try JSONEncoder().encode(JSON.object(body))

    return try await telemetry.step("ai.call", metadata: ["model": .string(model), "purpose": .string(purpose)]) { ctx in
      let started = Date()
      let (status, responseBody) = try await transport.post(endpoint, headers: headers, body: data)
      let latency = Date().timeIntervalSince(started) * 1000
      guard (200..<300).contains(status) else {
        let message = (try? JSONDecoder().decode(JSON.self, from: responseBody))?["error"]?["message"]?.stringValue ?? ""
        throw AIError.http(status: status, message: message)
      }
      guard let json = try? JSONDecoder().decode(JSON.self, from: responseBody), let content = json["content"]?.arrayValue else {
        throw AIError.badResponse
      }
      let u = json["usage"]
      let usage = AIUsage(
        model: json["model"]?.stringValue ?? model,
        inputTokens: Int(u?["input_tokens"]?.numberValue ?? 0), outputTokens: Int(u?["output_tokens"]?.numberValue ?? 0),
        cacheReadTokens: Int(u?["cache_read_input_tokens"]?.numberValue ?? 0),
        cacheWriteTokens: Int(u?["cache_creation_input_tokens"]?.numberValue ?? 0))
      ledger?.record(usage, purpose: purpose, latencyMs: latency)
      ctx.annotate("tokensIn", .int(usage.inputTokens))
      ctx.annotate("tokensOut", .int(usage.outputTokens))
      ctx.annotate("costUSD", .double(usage.costUSD))
      let stop = json["stop_reason"]?.stringValue ?? ""
      ctx.annotate("stop", .string(stop))
      if stop == "refusal" { throw AIError.refused }
      return Turn(content: content, stopReason: stop, usage: usage)
    }
  }

  /// Runs the client-side tool loop until Claude stops calling tools (or `maxTurns`).
  /// `execute` returns (result text, isError) for each tool call.
  public func runTools(
    model: String, system: String, user: String, tools: [AITool], maxTurns: Int = 6, effort: String? = nil, purpose: String,
    execute: @Sendable (String, JSON) async -> (String, Bool)
  ) async throws -> (text: String, calls: [(name: String, input: JSON)]) {
    var messages: [JSON] = [.object(["role": .string("user"), "content": .string(user)])]
    var calls: [(name: String, input: JSON)] = []
    for _ in 0..<maxTurns {
      let turn = try await send(model: model, system: system, messages: messages, tools: tools, effort: effort, purpose: purpose)
      messages.append(.object(["role": .string("assistant"), "content": .array(turn.content)]))
      let uses = turn.toolUses
      guard turn.stopReason == "tool_use", !uses.isEmpty else { return (turn.text, calls) }
      var results: [JSON] = []
      for use in uses {
        calls.append((use.name, use.input))
        let (output, isError) = await execute(use.name, use.input)
        results.append(.object([
          "type": .string("tool_result"), "tool_use_id": .string(use.id), "content": .string(output), "is_error": .bool(isError),
        ]))
      }
      // All results for one assistant turn go back in a single user message.
      messages.append(.object(["role": .string("user"), "content": .array(results)]))
    }
    return ("", calls)
  }
}
