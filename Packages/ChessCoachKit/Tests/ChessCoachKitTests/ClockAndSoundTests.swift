import ChessKit
import XCTest
@testable import ChessCoachKit

final class ChessClockTests: XCTestCase {
  let t0 = Date(timeIntervalSince1970: 0)

  func test_givenStartedClock_whenTimePasses_thenOnlySideToMoveLoses() {
    var clock = ChessClock(control: .init(base: 600, increment: 0))
    clock.start(.white, at: t0)
    XCTAssertEqual(clock.remaining(.white, at: t0 + 10), 590, accuracy: 0.001)
    XCTAssertEqual(clock.remaining(.black, at: t0 + 10), 600, accuracy: 0.001)
  }

  func test_givenIncrement_whenPressed_thenAddsIncrementAndSwitches() {
    var clock = ChessClock(control: .init(base: 900, increment: 10))
    clock.start(.white, at: t0)
    clock.press(.white, at: t0 + 5)
    XCTAssertEqual(clock.remaining(.white, at: t0 + 20), 905, accuracy: 0.001)
    XCTAssertEqual(clock.remaining(.black, at: t0 + 20), 885, accuracy: 0.001)
    XCTAssertEqual(clock.running, .black)
  }

  func test_givenTimeRunsOut_whenChecked_thenFlaggedColor() {
    var clock = ChessClock(control: .init(base: 60, increment: 0))
    clock.start(.white, at: t0)
    XCTAssertNil(clock.flagged(at: t0 + 59))
    XCTAssertEqual(clock.flagged(at: t0 + 60.1), .white)
    XCTAssertEqual(clock.remaining(.white, at: t0 + 70), 0)
  }

  func test_givenLowTime_whenChecked_thenLowBelowTenPercentOrTwentySeconds() {
    var clock = ChessClock(control: .init(base: 600, increment: 0))
    clock.start(.white, at: t0)
    XCTAssertFalse(clock.isLow(.white, at: t0 + 530))
    XCTAssertTrue(clock.isLow(.white, at: t0 + 541))
    var blitz = ChessClock(control: .init(base: 60, increment: 0))
    blitz.start(.white, at: t0)
    XCTAssertTrue(blitz.isLow(.white, at: t0 + 41))
  }

  func test_givenPausedClock_whenTimePasses_thenNoChange() {
    var clock = ChessClock(control: .init(base: 600, increment: 0))
    clock.start(.white, at: t0)
    clock.pause(at: t0 + 10)
    XCTAssertEqual(clock.remaining(.white, at: t0 + 100), 590, accuracy: 0.001)
    XCTAssertNil(clock.running)
  }

  func test_givenUntimedControl_whenQueried_thenNoFlagAndInfinite() {
    var clock = ChessClock(control: .untimed)
    clock.start(.white, at: t0)
    XCTAssertNil(clock.flagged(at: t0 + 100_000))
    XCTAssertFalse(clock.isLow(.white, at: t0 + 100_000))
    XCTAssertFalse(clock.control.isTimed)
  }

  func test_givenPresets_whenListed_thenLabelsMatch() {
    XCTAssertEqual(TimeControl.presets.map(\.label), ["No clock", "10 min", "15 | 10", "30 min"])
    XCTAssertEqual(TimeControl(base: 900, increment: 10).pgnTag, "900+10")
    XCTAssertEqual(TimeControl.untimed.pgnTag, "-")
  }
}

final class MoveSoundTests: XCTestCase {
  func sound(after ucis: [String], fen: String = GameSession.standardFEN) -> SoundEvent {
    var session = GameSession(startFEN: fen)
    var last: PlayedMove!
    for uci in ucis {
      guard case .applied(let p) = session.apply(uci: uci) else { fatalError(uci) }
      last = p
    }
    return SoundEvent.forMove(last, gameOver: session.isOver)
  }

  func test_givenQuietMove_whenMapped_thenMove() {
    XCTAssertEqual(sound(after: ["e2e4"]), .move)
  }

  func test_givenCapture_whenMapped_thenCapture() {
    XCTAssertEqual(sound(after: ["e2e4", "d7d5", "e4d5"]), .capture)
  }

  func test_givenCastle_whenMapped_thenCastle() {
    XCTAssertEqual(sound(after: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1"]), .castle)
  }

  func test_givenCheck_whenMapped_thenCheckBeatsCapture() {
    // 1.e4 d5 2.exd5 Qxd5 3.Nc3 Qe5+ (check, quiet) and a capture-with-check case
    XCTAssertEqual(sound(after: ["e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5e5"]), .check)
    XCTAssertEqual(sound(after: ["e2e4", "f7f6", "d1h5"]), .check)
  }

  func test_givenPromotion_whenMapped_thenPromote() {
    XCTAssertEqual(sound(after: ["e7e8q"], fen: "8/4P3/8/8/8/8/k7/4K3 w - - 0 1"), .promote)
  }

  func test_givenGameEndingMove_whenMapped_thenGameEnd() {
    XCTAssertEqual(sound(after: ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]), .gameEnd)
  }
}
