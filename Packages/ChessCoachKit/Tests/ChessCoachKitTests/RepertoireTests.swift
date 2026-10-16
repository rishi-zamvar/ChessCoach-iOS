import ChessKit
import XCTest
@testable import ChessCoachKit

final class RepertoireTests: XCTestCase {
  static let pgn = """
    [Event "Test repertoire"]
    [Side "white"]
    [Style "attacker"]
    [Name "Italian Game"]
    [Summary "Fast development and pressure on f7."]
    [Result "*"]

    1. e4 { Grab the centre. [%cal Ge2e4,Gd2d4] } 1... e5 (1... c5 2. Nf3 { Develop. }) 2. Nf3 { Hit e5. [%csl Re5] } 2... Nc6
    (2... d6 { [%dev] Philidor: solid but passive. } 3. d4 { Open the centre. })
    (2... Nf6 3. Nxe5 { Take the pawn. })
    3. Bc4 { Aim at f7. [%cal Gc4f7] } 3... Nf6 (3... Bc5 4. c3 { Prepare d4. }) 4. Ng5 { [%trap Fried Liver] Hit f7 twice! }
    *
    """

  func rep() throws -> Repertoire { try Repertoire(pgn: Self.pgn, fileName: "attacker-white") }

  func test_givenAnnotatedPGN_whenParsed_thenTagsAndTree() throws {
    let r = try rep()
    XCTAssertEqual(r.name, "Italian Game")
    XCTAssertEqual(r.side, .white)
    XCTAssertEqual(r.children(of: nil).map(\.san), ["e4"])
    let e4 = r.children(of: nil)[0]
    XCTAssertEqual(r.children(of: e4.id).map(\.san), ["e5", "c5"])
    XCTAssertEqual(e4.idea, "Grab the centre.")
    XCTAssertEqual(e4.arrows, [Arrow(from: Square("e2"), to: Square("e4"), color: .green), Arrow(from: Square("d2"), to: Square("d4"), color: .green)])
  }

  func test_givenVariations_whenParsed_thenSiblingsAndFlags() throws {
    let r = try rep()
    let e5 = r.nodes.first { $0.san == "e5" }!
    let nf3 = r.children(of: e5.id).first { $0.san == "Nf3" }!
    XCTAssertEqual(r.children(of: nf3.id).map(\.san), ["Nc6", "d6", "Nf6"])
    XCTAssertTrue(r.nodes.first { $0.san == "d6" }!.isDeviation)
    XCTAssertEqual(r.nodes.first { $0.san == "Ng5" }?.trap, "Fried Liver")
    XCTAssertEqual(r.trapCount, 1)
    XCTAssertEqual(nf3.highlights[Square("e5")], .red)
  }

  func test_givenTree_whenLinesListed_thenMainLineFirstAndAllLeaves() throws {
    let lines = try rep().lines
    XCTAssertEqual(lines.first?.map(\.san), ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6", "Ng5"])
    XCTAssertEqual(lines.count, 5)
  }

  func test_givenGameFollowingThenUserDeviating_whenCompared_thenUserLeft() throws {
    let d = try rep().departure(gameMoves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"], userColor: .white)
    XCTAssertEqual(d, .userLeft(ply: 5, played: "Bb5", expected: ["Bc4"]))
  }

  func test_givenOpponentLeavesBook_whenCompared_thenOpponentLeft() throws {
    let d = try rep().departure(gameMoves: ["e2e4", "e7e6", "d2d4"], userColor: .white)
    XCTAssertEqual(d, .opponentLeft(ply: 2, played: "e6"))
  }

  func test_givenWrongColor_whenCompared_thenNil() throws {
    XCTAssertNil(try rep().departure(gameMoves: ["e2e4"], userColor: .black))
  }

  func test_givenIllegalMove_whenParsed_thenThrows() {
    XCTAssertThrowsError(try Repertoire(pgn: "[Side \"white\"]\n\n1. e5 *", fileName: "bad"))
  }

  func test_givenUnbalancedVariation_whenParsed_thenThrows() {
    XCTAssertThrowsError(try Repertoire(pgn: "[Side \"white\"]\n\n1. e4 (1. d4 *", fileName: "bad"))
  }
}
