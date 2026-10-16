import Foundation
import os

/// Anything that persists or displays step events.
public protocol TelemetrySink: Sendable {
  func record(_ event: StepEvent)
}

/// Handle passed into a running step for progress and extra finish metadata.
public final class StepContext: @unchecked Sendable {
  public let id: UUID
  public let runID: UUID
  let step: String
  private let telemetry: Telemetry
  private let lock = NSLock()
  private var extra: [String: JSONValue] = [:]

  init(id: UUID, runID: UUID, step: String, telemetry: Telemetry) {
    self.id = id
    self.runID = runID
    self.step = step
    self.telemetry = telemetry
  }

  /// Reports progress (e.g. analysing ply 12 of 80).
  public func progress(done: Int, total: Int) {
    telemetry.emit(StepEvent(id: id, runID: runID, parentID: nil, step: step, phase: .progress, done: done, total: total))
  }

  /// Adds a key/value to the finish (or fail) event.
  public func annotate(_ key: String, _ value: JSONValue) {
    lock.withLock { extra[key] = value }
  }

  var annotations: [String: JSONValue] { lock.withLock { extra } }
}

/// Structured step logging fan-out (os.Logger, database, live streams).
///
/// Usage: `try await telemetry.step("analysis.ply", parent: ctx) { ctx in ... }`.
public final class Telemetry: Sendable {
  private let sinks: [TelemetrySink]
  private let subscribers = OSAllocatedUnfairLock<[UUID: AsyncStream<StepEvent>.Continuation]>(initialState: [:])

  public init(sinks: [TelemetrySink]) {
    self.sinks = sinks
  }

  /// A telemetry instance that only writes to os.Logger.
  public static let logOnly = Telemetry(sinks: [OSLogSink()])

  /// Runs `body` as a logged step: start, then finish (with duration) or fail (and rethrow).
  @discardableResult
  public func step<T>(
    _ name: String,
    parent: StepContext? = nil,
    metadata: [String: JSONValue] = [:],
    isolation: isolated (any Actor)? = #isolation,
    _ body: (StepContext) async throws -> T
  ) async rethrows -> T {
    let id = UUID()
    let runID = parent?.runID ?? UUID()
    let ctx = StepContext(id: id, runID: runID, step: name, telemetry: self)
    let started = ContinuousClock.now
    emit(StepEvent(id: id, runID: runID, parentID: parent?.id, step: name, phase: .start, metadata: metadata))
    do {
      let value = try await body(ctx)
      emit(StepEvent(
        id: id, runID: runID, parentID: parent?.id, step: name, phase: .finish,
        durationMs: Self.ms(since: started), metadata: metadata.merging(ctx.annotations) { _, new in new }))
      return value
    } catch {
      emit(StepEvent(
        id: id, runID: runID, parentID: parent?.id, step: name, phase: .fail,
        durationMs: Self.ms(since: started), metadata: metadata.merging(ctx.annotations) { _, new in new },
        error: String(describing: error)))
      throw error
    }
  }

  /// Records a single-shot event (no duration), e.g. a user tap or a state change.
  public func event(_ name: String, parent: StepContext? = nil, metadata: [String: JSONValue] = [:]) {
    emit(StepEvent(
      id: UUID(), runID: parent?.runID ?? UUID(), parentID: parent?.id, step: name, phase: .finish,
      metadata: metadata))
  }

  /// A live stream of every event emitted from now on (progress bars, timers, debug views).
  public func events() -> AsyncStream<StepEvent> {
    let key = UUID()
    let (stream, continuation) = AsyncStream<StepEvent>.makeStream(bufferingPolicy: .bufferingNewest(500))
    continuation.onTermination = { [weak self] _ in
      self?.subscribers.withLock { _ = $0.removeValue(forKey: key) }
    }
    subscribers.withLock { $0[key] = continuation }
    return stream
  }

  func emit(_ event: StepEvent) {
    for sink in sinks { sink.record(event) }
    let conts = subscribers.withLock { Array($0.values) }
    for c in conts { c.yield(event) }
  }

  private static func ms(since start: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - start
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
  }
}
