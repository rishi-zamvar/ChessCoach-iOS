import ChessKit
import CoreGraphics
import XCTest
@testable import ChessCoachKit

final class BoardGeometryTests: XCTestCase {
  func test_givenWhiteOrientation_whenMappingCorners_thenA1BottomLeftH8TopRight() {
    let g = BoardGeometry(size: 800, flipped: false)
    XCTAssertEqual(g.square(at: CGPoint(x: 10, y: 790)), Square("a1"))
    XCTAssertEqual(g.square(at: CGPoint(x: 790, y: 10)), Square("h8"))
    XCTAssertEqual(g.center(of: Square("e4")), CGPoint(x: 450, y: 450))
  }

  func test_givenFlipped_whenMappingCorners_thenH8BottomLeft() {
    let g = BoardGeometry(size: 800, flipped: true)
    XCTAssertEqual(g.square(at: CGPoint(x: 10, y: 790)), Square("h8"))
    XCTAssertEqual(g.square(at: CGPoint(x: 790, y: 10)), Square("a1"))
  }

  func test_givenAnySquare_whenRoundTrippedThroughCenter_thenSameSquare() {
    for flipped in [false, true] {
      let g = BoardGeometry(size: 360, flipped: flipped)
      for square in Square.allCases {
        XCTAssertEqual(g.square(at: g.center(of: square)), square)
      }
    }
  }

  func test_givenPointOutsideBoard_whenMapped_thenNil() {
    XCTAssertNil(BoardGeometry(size: 100, flipped: false).square(at: CGPoint(x: -1, y: 5)))
    XCTAssertNil(BoardGeometry(size: 100, flipped: false).square(at: CGPoint(x: 5, y: 100)))
  }

  func test_givenSquares_whenColored_thenA1DarkH1Light() {
    XCTAssertFalse(BoardGeometry.isLightSquare(Square("a1")))
    XCTAssertTrue(BoardGeometry.isLightSquare(Square("h1")))
  }

  func test_givenMove_whenReconciled_thenMovedPieceKeepsIdentity() {
    var nextID = 0
    let start = PieceIdentity.reconcile(previous: [], next: Position.standard.pieces, nextID: &nextID)
    XCTAssertEqual(nextID, 32)
    var session = GameSession()
    session.apply(uci: "e2e4")
    let after = PieceIdentity.reconcile(previous: start, next: session.position.pieces, nextID: &nextID)
    let oldE2 = start.first { $0.piece.square == Square("e2") }!.id
    XCTAssertEqual(after.first { $0.piece.square == Square("e4") }?.id, oldE2)
    XCTAssertEqual(Set(after.map(\.id)).count, 32)
    XCTAssertEqual(nextID, 32)
  }

  func test_givenCapture_whenReconciled_thenCapturedIdentityDropped() {
    var nextID = 0
    var session = GameSession()
    for m in ["e2e4", "d7d5"] { session.apply(uci: m) }
    let before = PieceIdentity.reconcile(previous: [], next: session.position.pieces, nextID: &nextID)
    session.apply(uci: "e4d5")
    let after = PieceIdentity.reconcile(previous: before, next: session.position.pieces, nextID: &nextID)
    XCTAssertEqual(after.count, 31)
    XCTAssertEqual(after.first { $0.piece.square == Square("d5") }?.id, before.first { $0.piece.square == Square("e4") }?.id)
  }
}
