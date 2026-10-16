import XCTest
@testable import ChessCoachKit

final class TelemetryTests: XCTestCase {
  struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }

  func test_givenSucceedingStep_whenRun_thenEmitsStartAndFinishWithSameRun() async throws {
    let sink = MemorySink()
    let telemetry = Telemetry(sinks: [sink])
    let value = await telemetry.step("unit.ok") { _ in 42 }
    XCTAssertEqual(value, 42)
    let events = sink.events
    XCTAssertEqual(events.map(\.phase), [.start, .finish])
    XCTAssertEqual(events[0].id, events[1].id)
    XCTAssertEqual(events[0].runID, events[1].runID)
    XCTAssertGreaterThanOrEqual(events[1].durationMs ?? -1, 0)
    XCTAssertEqual(events.map(\.step), ["unit.ok", "unit.ok"])
  }

  func test_givenThrowingStep_whenRun_thenEmitsFailWithErrorAndRethrows() async {
    let sink = MemorySink()
    let telemetry = Telemetry(sinks: [sink])
    do {
      try await telemetry.step("unit.fail") { _ in throw Boom() }
      XCTFail("expected throw")
    } catch {
      XCTAssertTrue(error is Boom)
    }
    XCTAssertEqual(sink.events.map(\.phase), [.start, .fail])
    XCTAssertEqual(sink.events.last?.error, "boom")
    XCTAssertNotNil(sink.events.last?.durationMs)
  }

  func test_givenNestedSteps_whenRun_thenChildCarriesParentIDAndRunID() async {
    let sink = MemorySink()
    let telemetry = Telemetry(sinks: [sink])
    await telemetry.step("outer") { outer in
      await telemetry.step("inner", parent: outer) { _ in }
    }
    let outerStart = sink.events.first { $0.step == "outer" }!
    let innerStart = sink.events.first { $0.step == "inner" }!
    XCTAssertEqual(innerStart.parentID, outerStart.id)
    XCTAssertEqual(innerStart.runID, outerStart.runID)
  }

  func test_givenProgressCalls_whenRun_thenProgressEventsCarryCounts() async {
    let sink = MemorySink()
    let telemetry = Telemetry(sinks: [sink])
    await telemetry.step("unit.progress") { ctx in
      ctx.progress(done: 1, total: 3)
      ctx.progress(done: 3, total: 3)
    }
    let progress = sink.events.filter { $0.phase == .progress }
    XCTAssertEqual(progress.map(\.done), [1, 3])
    XCTAssertEqual(progress.map(\.total), [3, 3])
  }

  func test_givenAnnotate_whenStepFinishes_thenFinishMetadataIncludesValue() async {
    let sink = MemorySink()
    let telemetry = Telemetry(sinks: [sink])
    await telemetry.step("unit.meta", metadata: ["a": .int(1)]) { ctx in
      ctx.annotate("b", .string("x"))
    }
    let finish = sink.events.last!
    XCTAssertEqual(finish.metadata["a"], .int(1))
    XCTAssertEqual(finish.metadata["b"], .string("x"))
  }

  func test_givenSubscriber_whenEventsEmitted_thenReceivesThemInOrder() async {
    let telemetry = Telemetry(sinks: [])
    let stream = telemetry.events()
    let collector = Task {
      var phases: [StepPhase] = []
      for await event in stream {
        phases.append(event.phase)
        if phases.count == 2 { break }
      }
      return phases
    }
    await telemetry.step("unit.stream") { _ in }
    let phases = await collector.value
    XCTAssertEqual(phases, [.start, .finish])
  }

  func test_givenSingleShotEvent_whenRecorded_thenOneFinishEvent() {
    let sink = MemorySink()
    let telemetry = Telemetry(sinks: [sink])
    telemetry.event("unit.single", metadata: ["k": .bool(true)])
    XCTAssertEqual(sink.events.count, 1)
    XCTAssertEqual(sink.events[0].phase, .finish)
    XCTAssertEqual(sink.events[0].metadata["k"], .bool(true))
  }

  func test_givenJSONValue_whenEncoded_thenRoundTrips() throws {
    let value: [String: JSONValue] = ["s": .string("a"), "i": .int(2), "d": .double(1.5), "b": .bool(false), "n": .null]
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode([String: JSONValue].self, from: data), value)
  }
}
