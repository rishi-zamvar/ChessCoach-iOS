import Foundation
import os

/// Writes events to the unified log (Console.app, subsystem `com.rishi.chesscoach`).
public struct OSLogSink: TelemetrySink {
  private let logger = Logger(subsystem: "com.rishi.chesscoach", category: "step")

  public init() {}

  public func record(_ event: StepEvent) {
    let meta = event.metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.description)" }.joined(separator: " ")
    let duration = event.durationMs.map { String(format: "%.1fms", $0) } ?? ""
    let progress = event.total.map { "\(event.done ?? 0)/\($0)" } ?? ""
    switch event.phase {
    case .fail:
      logger.error(
        "\(event.step, privacy: .public) fail \(duration, privacy: .public) \(meta, privacy: .private) error=\(event.error ?? "", privacy: .public)"
      )
    case .progress:
      logger.debug("\(event.step, privacy: .public) progress \(progress, privacy: .public)")
    default:
      logger.info(
        "\(event.step, privacy: .public) \(event.phase.rawValue, privacy: .public) \(duration, privacy: .public) \(meta, privacy: .private)"
      )
    }
  }
}

/// Keeps events in memory (tests, debug overlay).
public final class MemorySink: TelemetrySink, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [StepEvent] = []

  public init() {}

  public func record(_ event: StepEvent) {
    lock.withLock { storage.append(event) }
  }

  public var events: [StepEvent] { lock.withLock { storage } }

  public func events(named step: String) -> [StepEvent] { events.filter { $0.step == step } }
}
