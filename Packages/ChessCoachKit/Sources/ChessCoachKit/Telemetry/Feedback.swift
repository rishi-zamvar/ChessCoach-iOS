import Foundation

/// One in-app feedback report, in the shape `POST /v1/feedback` takes (spec W8).
public struct FeedbackReport: Codable, Equatable, Sendable, Identifiable {
  public enum Category: String, Codable, Sendable, CaseIterable {
    case bug, confusing, idea, praise, none
  }

  public var id: UUID
  public var category: Category
  public var text: String
  public var screen: String
  public var context: [String: JSONValue]
  public var breadcrumbs: [String]
  public var build: String
  public var appVersion: String
  /// Base64 JPEG.
  public var screenshot: String?

  enum CodingKeys: String, CodingKey {
    case id, category, text, screen, context, breadcrumbs, build, screenshot
    case appVersion = "app_version"
  }

  /// Builds a report; with `diagnostics` off only the words, category and screenshot are sent.
  public static func make(
    id: UUID, category: Category, text: String, screen: String, context: [String: JSONValue], breadcrumbs: [String],
    build: String, appVersion: String, screenshotJPEG: Data?, diagnostics: Bool
  ) -> FeedbackReport {
    let cleanContext = diagnostics
      ? Dictionary(uniqueKeysWithValues: context.compactMap { k, v in feedbackScrub(key: k, v).map { (k, $0) } }.prefix(60))
      : [:]
    return FeedbackReport(
      id: id, category: category, text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)),
      screen: diagnostics ? screen : "", context: cleanContext,
      breadcrumbs: diagnostics ? Array(breadcrumbs.suffix(50)) : [], build: build, appVersion: appVersion,
      screenshot: screenshotJPEG?.base64EncodedString())
  }

  /// Like analytics scrubbing, but a FEN (~90 chars) is useful context here.
  static func feedbackScrub(key: String, _ value: JSONValue) -> JSONValue? {
    if key == "fen" { return value }
    return AnalyticsEvent.scrub(key: key, value)
  }
}

/// The last `capacity` telemetry steps as short lines ("screen.view name=today"), scrubbed, for feedback context.
public final class BreadcrumbSink: TelemetrySink, @unchecked Sendable {
  private let lock = NSLock()
  private let capacity: Int
  private var buffer: [String] = []

  public init(capacity: Int = 50) {
    self.capacity = capacity
  }

  public func record(_ event: StepEvent) {
    guard event.phase != .progress, event.phase != .start else { return }
    let meta = event.metadata.sorted { $0.key < $1.key }
      .compactMap { k, v in AnalyticsEvent.scrub(key: k, v).map { "\(k)=\($0.description)" } }
    let line = ([event.step + (event.phase == .fail ? " FAIL" : "")] + meta).joined(separator: " ").prefix(200)
    lock.withLock {
      buffer.append(String(line))
      if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
    }
  }

  public var lines: [String] { lock.withLock { buffer } }
}

/// Reports waiting to be sent: one JSON file each, so nothing typed is lost offline or on a crash.
public final class FeedbackOutbox: @unchecked Sendable {
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  public func enqueue(_ report: FeedbackReport) throws {
    try JSONEncoder().encode(report).write(to: file(report.id), options: .atomic)
  }

  public func pending() -> [FeedbackReport] {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
    return files.filter { $0.pathExtension == "json" }
      .compactMap { try? JSONDecoder().decode(FeedbackReport.self, from: Data(contentsOf: $0)) }
  }

  /// Tries every pending report; the ones `send` accepts are removed, the rest wait for next time.
  public func flush(_ send: (FeedbackReport) async throws -> Void) async {
    for report in pending() {
      do {
        try await send(report)
        try? FileManager.default.removeItem(at: file(report.id))
      } catch {
        continue
      }
    }
  }

  private func file(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }
}
