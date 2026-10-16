import XCTest
@testable import ChessCoachKit

final class CurriculumTests: XCTestCase {
  let curriculum = Curriculum.shared

  func test_givenBundledCurriculum_whenLoaded_thenVersionOneWithAtLeast15Lessons() {
    XCTAssertEqual(curriculum.version, 1)
    XCTAssertGreaterThanOrEqual(curriculum.lessons.count, 15)
  }

  func test_givenLessons_whenComparingIds_thenAllUnique() {
    let ids = curriculum.lessons.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count)
  }

  func test_givenLessons_whenFollowingPrerequisites_thenAllExistAndNoCycles() {
    let byID = Dictionary(uniqueKeysWithValues: curriculum.lessons.map { ($0.id, $0) })
    for lesson in curriculum.lessons {
      for p in lesson.prerequisites { XCTAssertNotNil(byID[p], "\(lesson.id) needs unknown \(p)") }
    }
    var state: [String: Int] = [:]  // 1 visiting, 2 done
    func visit(_ id: String) -> Bool {
      if state[id] == 1 { return false }
      if state[id] == 2 { return true }
      state[id] = 1
      defer { state[id] = 2 }
      return (byID[id]?.prerequisites ?? []).allSatisfy(visit)
    }
    for lesson in curriculum.lessons { XCTAssertTrue(visit(lesson.id), "cycle through \(lesson.id)") }
  }

  func test_givenEveryWorkedExample_whenReplayed_thenAllMovesLegalAndNarrationAndArrowsMatch() {
    for lesson in curriculum.lessons {
      let ex = lesson.worked
      XCTAssertEqual(ex.narration.count, ex.moves.count, lesson.id)
      XCTAssertEqual(ex.arrows.count, ex.moves.count, lesson.id)
      var session = GameSession(startFEN: ex.fen)
      XCTAssertEqual(session.startFEN, ex.fen)
      for uci in ex.moves {
        guard case .applied = session.apply(uci: uci) else {
          return XCTFail("\(lesson.id): worked move \(uci) illegal")
        }
      }
    }
  }

  func test_givenEveryFadedExample_whenSolutionPlayed_thenAllMovesLegal() {
    for lesson in curriculum.lessons {
      var session = GameSession(startFEN: lesson.faded.fen)
      for uci in lesson.faded.solution {
        guard case .applied = session.apply(uci: uci) else {
          return XCTFail("\(lesson.id): faded move \(uci) illegal")
        }
      }
    }
  }

  func test_givenMateLessons_whenFadedSolved_thenCheckmate() {
    for lesson in curriculum.lessons where lesson.title.lowercased().contains("mate") {
      var session = GameSession(startFEN: lesson.faded.fen)
      lesson.faded.solution.forEach { session.apply(uci: $0) }
      XCTAssertEqual(session.result?.termination, .checkmate, lesson.id)
    }
  }

  func test_givenPracticeSpecs_whenInspected_thenEachKindHasItsFields() {
    for lesson in curriculum.lessons {
      let p = lesson.practice
      XCTAssertGreaterThan(p.count, 0, lesson.id)
      switch p.kind {
      case .puzzles:
        XCTAssertFalse(p.themes?.isEmpty ?? true, lesson.id)
        XCTAssertEqual(p.rating?.count, 2, lesson.id)
      case .playout:
        XCTAssertNotNil(p.fen, lesson.id)
        XCTAssertNotNil(p.goal, lesson.id)
      default: break
      }
      XCTAssertLessThanOrEqual(lesson.mastery.required, lesson.mastery.of, lesson.id)
    }
  }

  func test_givenCurriculum_whenLookingUpById_thenFindsLesson() {
    XCTAssertEqual(curriculum.lesson(id: "C2")?.title, "The knight fork")
    XCTAssertNil(curriculum.lesson(id: "nope"))
  }

  func test_givenBeginnerRating_whenFilteringByBand_thenBoardBasicsIncludedAndOppositionExcluded() {
    let ids = curriculum.lessons(forRating: 300).map(\.id)
    XCTAssertTrue(ids.contains("A1"))
    XCTAssertTrue(ids.contains("B1"))
    XCTAssertFalse(ids.contains("E3"))
  }
}
