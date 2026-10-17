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

/// Where the coach's language model lives. Two wire formats cover them all: Anthropic's
/// Messages API, and OpenAI's Chat Completions (also served by Gemini, OpenRouter, Ollama,
/// LM Studio and most other hosts).
public enum LLMProvider: String, CaseIterable, Codable, Sendable, Identifiable {
  case anthropic, openai, gemini, openrouter, custom

  public enum Wire: Sendable { case anthropic, openai }

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .anthropic: "Claude (Anthropic)"
    case .openai: "OpenAI"
    case .gemini: "Gemini (Google)"
    case .openrouter: "OpenRouter"
    case .custom: "Other (OpenAI-compatible)"
    }
  }

  public var wire: Wire { self == .anthropic ? .anthropic : .openai }

  /// Base URL the endpoint path is appended to (custom: the user's server).
  public var defaultBaseURL: String {
    switch self {
    case .anthropic: "https://api.anthropic.com/v1"
    case .openai: "https://api.openai.com/v1"
    case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
    case .openrouter: "https://openrouter.ai/api/v1"
    case .custom: "http://localhost:11434/v1"
    }
  }

  /// Default models (editable in Settings): fast for per-move coaching, smart for questions.
  public var defaultModels: (fast: String, smart: String) {
    switch self {
    case .anthropic: ("claude-haiku-4-5", "claude-sonnet-5-5")
    case .openai: ("gpt-5-mini", "gpt-5")
    case .gemini: ("gemini-2.5-flash", "gemini-2.5-pro")
    case .openrouter: ("anthropic/claude-haiku-4.5", "anthropic/claude-sonnet-4.5")
    case .custom: ("llama3.1", "llama3.1")
    }
  }

  /// Local servers (Ollama etc.) often take no key.
  public var needsKey: Bool { self != .custom }
}

/// Which model a call wants: fast (per-move, latency-bound) or smart (open questions).
public enum LLMTier: String, Sendable { case fast, smart }

/// Everything needed to reach one provider.
public struct LLMConfig: Sendable, Equatable {
  public var provider: LLMProvider
  public var apiKey: String?
  public var baseURL: URL
  public var fastModel: String
  public var smartModel: String

  public init(provider: LLMProvider, apiKey: String?, baseURL: URL? = nil, fastModel: String? = nil, smartModel: String? = nil) {
    self.provider = provider
    self.apiKey = apiKey
    self.baseURL = baseURL ?? URL(string: provider.defaultBaseURL)!
    self.fastModel = fastModel ?? provider.defaultModels.fast
    self.smartModel = smartModel ?? provider.defaultModels.smart
  }

  public func model(_ tier: LLMTier) -> String { tier == .fast ? fastModel : smartModel }

  var isUsable: Bool { !provider.needsKey || !(apiKey ?? "").isEmpty }
}

/// Provider-agnostic chat client with a client-side tool loop. Callers speak one canonical
/// format (Anthropic-style content blocks: text / tool_use / tool_result); the OpenAI wire
/// format is translated on the way out and back.
public struct LLMClient: Sendable {
  let config: @Sendable () -> LLMConfig?
  let transport: AITransport
  let telemetry: Telemetry
  let ledger: AISpendLedger?
  let monthlyCapUSD: Double

  public init(
    config: @escaping @Sendable () -> LLMConfig?, transport: AITransport = URLSessionAITransport(),
    telemetry: Telemetry, ledger: AISpendLedger?, monthlyCapUSD: Double = 80
  ) {
    self.config = config
    self.transport = transport
    self.telemetry = telemetry
    self.ledger = ledger
    self.monthlyCapUSD = monthlyCapUSD
  }

  /// Calls stop a little before the cap so parallel/looping calls can't overshoot it.
  var effectiveCap: Double { monthlyCapUSD * 0.98 }

  public var isAvailable: Bool { config()?.isUsable == true && (ledger?.spentThisMonth() ?? 0) < effectiveCap }

  /// The model name a tier resolves to right now (cache keys, logs).
  public func model(_ tier: LLMTier) -> String { config()?.model(tier) ?? tier.rawValue }

  public struct Turn: Sendable {
    /// Assistant content blocks in canonical form (echoed back when continuing).
    public var content: [JSON]
    /// Canonical: end_turn, tool_use, max_tokens, refusal.
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

  /// One chat call. `effort` is a hint (Anthropic only).
  public func send(
    tier: LLMTier, system: String, messages: [JSON], tools: [AITool] = [], maxTokens: Int = 1024,
    effort: String? = nil, purpose: String
  ) async throws -> Turn {
    guard let config = config(), config.isUsable else { throw AIError.noKey }
    let spent = ledger?.spentThisMonth() ?? 0
    guard spent < effectiveCap else { throw AIError.budgetExceeded(spentUSD: spent) }
    let model = config.model(tier)
    let request =
      config.provider.wire == .anthropic
      ? Self.anthropicRequest(config, model: model, system: system, messages: messages, tools: tools, maxTokens: maxTokens, effort: effort)
      : Self.openAIRequest(config, model: model, system: system, messages: messages, tools: tools, maxTokens: maxTokens)
    let data = try JSONEncoder().encode(JSON.object(request.body))

    return try await telemetry.step(
      "ai.call", metadata: ["model": .string(model), "provider": .string(config.provider.rawValue), "purpose": .string(purpose)]
    ) { ctx in
      let started = Date()
      let (status, responseBody) = try await transport.post(request.url, headers: request.headers, body: data)
      let latency = Date().timeIntervalSince(started) * 1000
      let json = try? JSONDecoder().decode(JSON.self, from: responseBody)
      guard (200..<300).contains(status) else {
        throw AIError.http(status: status, message: json?["error"]?["message"]?.stringValue ?? json?["error"]?.stringValue ?? "")
      }
      guard let json,
        let turn = config.provider.wire == .anthropic ? Self.anthropicTurn(json, model: model) : Self.openAITurn(json, model: model)
      else { throw AIError.badResponse }
      ledger?.record(turn.usage, purpose: purpose, latencyMs: latency)
      ctx.annotate("tokensIn", .int(turn.usage.inputTokens))
      ctx.annotate("tokensOut", .int(turn.usage.outputTokens))
      ctx.annotate("costUSD", .double(turn.usage.costUSD))
      ctx.annotate("stop", .string(turn.stopReason))
      if turn.stopReason == "refusal" { throw AIError.refused }
      return turn
    }
  }

  /// Runs the client-side tool loop until the model stops calling tools (or `maxTurns`).
  /// `execute` returns (result text, isError) for each tool call.
  public func runTools(
    tier: LLMTier, system: String, user: String, tools: [AITool], maxTurns: Int = 6, effort: String? = nil, purpose: String,
    execute: @Sendable (String, JSON) async -> (String, Bool)
  ) async throws -> (text: String, calls: [(name: String, input: JSON)]) {
    var messages: [JSON] = [.object(["role": .string("user"), "content": .string(user)])]
    var calls: [(name: String, input: JSON)] = []
    for _ in 0..<maxTurns {
      let turn = try await send(tier: tier, system: system, messages: messages, tools: tools, effort: effort, purpose: purpose)
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

  // MARK: - Anthropic Messages

  struct Request {
    var url: URL
    var headers: [String: String]
    var body: [String: JSON]
  }

  static func anthropicRequest(
    _ c: LLMConfig, model: String, system: String, messages: [JSON], tools: [AITool], maxTokens: Int, effort: String?
  ) -> Request {
    var body: [String: JSON] = [
      "model": .string(model),
      "max_tokens": .number(Double(maxTokens)),
      "system": .array([.object(["type": .string("text"), "text": .string(system), "cache_control": .object(["type": .string("ephemeral")])])]),
      "messages": .array(messages),
    ]
    if !tools.isEmpty { body["tools"] = .array(tools.map(\.json)) }
    if let effort { body["output_config"] = .object(["effort": .string(effort)]) }
    var headers = ["content-type": "application/json", "x-api-key": c.apiKey ?? "", "anthropic-version": "2023-06-01"]
    if model.hasPrefix("claude-sonnet-5-5") {
      // Server-side refusal fallback (Claude API, Sonnet 5.5: "default" form only).
      body["fallbacks"] = .string("default")
      headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
    }
    return Request(url: c.baseURL.appendingPathComponent("messages"), headers: headers, body: body)
  }

  static func anthropicTurn(_ json: JSON, model: String) -> Turn? {
    guard let content = json["content"]?.arrayValue else { return nil }
    let u = json["usage"]
    let usage = AIUsage(
      model: json["model"]?.stringValue ?? model,
      inputTokens: Int(u?["input_tokens"]?.numberValue ?? 0), outputTokens: Int(u?["output_tokens"]?.numberValue ?? 0),
      cacheReadTokens: Int(u?["cache_read_input_tokens"]?.numberValue ?? 0),
      cacheWriteTokens: Int(u?["cache_creation_input_tokens"]?.numberValue ?? 0))
    return Turn(content: content, stopReason: json["stop_reason"]?.stringValue ?? "", usage: usage)
  }

  // MARK: - OpenAI Chat Completions

  static func openAIRequest(_ c: LLMConfig, model: String, system: String, messages: [JSON], tools: [AITool], maxTokens: Int) -> Request {
    var out: [JSON] = [.object(["role": .string("system"), "content": .string(system)])]
    for m in messages { out += openAIMessages(m) }
    var body: [String: JSON] = ["model": .string(model), "messages": .array(out)]
    // OpenAI's own API wants max_completion_tokens (reasoning models reject max_tokens); others take max_tokens.
    body[c.provider == .openai ? "max_completion_tokens" : "max_tokens"] = .number(Double(maxTokens))
    if !tools.isEmpty {
      body["tools"] = .array(tools.map { t in
        .object(["type": .string("function"), "function": .object([
          "name": .string(t.name), "description": .string(t.description), "parameters": t.inputSchema,
        ])])
      })
    }
    var headers = ["content-type": "application/json"]
    if let key = c.apiKey, !key.isEmpty { headers["authorization"] = "Bearer \(key)" }
    return Request(url: c.baseURL.appendingPathComponent("chat/completions"), headers: headers, body: body)
  }

  /// One canonical message → OpenAI messages (tool results become separate "tool" messages).
  static func openAIMessages(_ m: JSON) -> [JSON] {
    let role = m["role"]?.stringValue ?? "user"
    guard let blocks = m["content"]?.arrayValue else { return [m] }
    if role == "assistant" {
      let text = blocks.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined()
      let calls: [JSON] = blocks.compactMap { b in
        guard b["type"]?.stringValue == "tool_use", let id = b["id"], let name = b["name"] else { return nil }
        return .object(["id": id, "type": .string("function"), "function": .object(["name": name, "arguments": .string((b["input"] ?? .object([:])).text)])])
      }
      var msg: [String: JSON] = ["role": .string("assistant"), "content": text.isEmpty ? .null : .string(text)]
      if !calls.isEmpty { msg["tool_calls"] = .array(calls) }
      return [.object(msg)]
    }
    var out: [JSON] = []
    var texts: [String] = []
    for b in blocks {
      switch b["type"]?.stringValue {
      case "tool_result":
        out.append(.object(["role": .string("tool"), "tool_call_id": b["tool_use_id"] ?? .null, "content": b["content"] ?? .string("")]))
      case "text": texts.append(b["text"]?.stringValue ?? "")
      default: break
      }
    }
    if !texts.isEmpty { out.append(.object(["role": .string(role), "content": .string(texts.joined(separator: "\n"))])) }
    return out
  }

  static func openAITurn(_ json: JSON, model: String) -> Turn? {
    guard let choice = json["choices"]?.arrayValue?.first, let message = choice["message"] else { return nil }
    var content: [JSON] = []
    if let text = message["content"]?.stringValue, !text.isEmpty {
      content.append(.object(["type": .string("text"), "text": .string(text)]))
    }
    for call in message["tool_calls"]?.arrayValue ?? [] {
      let args = call["function"]?["arguments"]?.stringValue ?? "{}"
      let input = (try? JSONDecoder().decode(JSON.self, from: Data(args.utf8))) ?? .object([:])
      content.append(.object([
        "type": .string("tool_use"), "id": call["id"] ?? .string(UUID().uuidString), "name": call["function"]?["name"] ?? .string(""),
        "input": input,
      ]))
    }
    let finish = choice["finish_reason"]?.stringValue ?? ""
    let hasCalls = content.contains { $0["type"]?.stringValue == "tool_use" }
    let stop =
      hasCalls ? "tool_use" : finish == "length" ? "max_tokens" : finish == "content_filter" || message["refusal"]?.stringValue != nil ? "refusal" : "end_turn"
    let u = json["usage"]
    let cached = Int(u?["prompt_tokens_details"]?["cached_tokens"]?.numberValue ?? 0)
    let usage = AIUsage(
      model: json["model"]?.stringValue ?? model, inputTokens: Int(u?["prompt_tokens"]?.numberValue ?? 0) - cached,
      outputTokens: Int(u?["completion_tokens"]?.numberValue ?? 0), cacheReadTokens: cached, cacheWriteTokens: 0)
    return Turn(content: content, stopReason: stop, usage: usage)
  }
}
