import ChessKit
import XCTest
@testable import ChessCoachKit

final class BoardInteractionTests: XCTestCase {
  let e2 = Square("e2"), e4 = Square("e4"), d2 = Square("d2"), e7 = Square("e7"), e5 = Square("e5")

  func test_givenUserTurn_whenTappingOwnPiece_thenSelectsWithTargets() {
    var interaction = BoardInteraction()
    let result = interaction.tap(e2, session: GameSession(), userColor: .white)
    XCTAssertEqual(result, .selected(e2))
    XCTAssertEqual(interaction.selected, e2)
    XCTAssertEqual(Set(interaction.legalTargets), [Square("e3"), e4])
  }

  func test_givenSelection_whenTappingTarget_thenMoveAndClear() {
    var interaction = BoardInteraction()
    let session = GameSession()
    interaction.tap(e2, session: session, userColor: .white)
    XCTAssertEqual(interaction.tap(e4, session: session, userColor: .white), .move(from: e2, to: e4))
    XCTAssertNil(interaction.selected)
    XCTAssertTrue(interaction.legalTargets.isEmpty)
  }

  func test_givenSelection_whenTappingAnotherOwnPiece_thenReselects() {
    var interaction = BoardInteraction()
    let session = GameSession()
    interaction.tap(e2, session: session, userColor: .white)
    XCTAssertEqual(interaction.tap(d2, session: session, userColor: .white), .selected(d2))
  }

  func test_givenSelection_whenTappingSameSquare_thenDeselects() {
    var interaction = BoardInteraction()
    let session = GameSession()
    interaction.tap(e2, session: session, userColor: .white)
    XCTAssertEqual(interaction.tap(e2, session: session, userColor: .white), .deselected)
    XCTAssertNil(interaction.selected)
  }

  func test_givenSelection_whenTappingEmptyNonTarget_thenDeselects() {
    var interaction = BoardInteraction()
    let session = GameSession()
    interaction.tap(e2, session: session, userColor: .white)
    XCTAssertEqual(interaction.tap(Square("a5"), session: session, userColor: .white), .deselected)
  }

  func test_givenOpponentTurn_whenUserSelectsAndTapsDestination_thenPremoveQueued() {
    var interaction = BoardInteraction()
    var session = GameSession()
    session.apply(uci: "e2e4")  // now black (bot) to move, user is white
    interaction.tap(d2, session: session, userColor: .white)
    XCTAssertEqual(interaction.selected, d2)
    XCTAssertEqual(interaction.tap(Square("d4"), session: session, userColor: .white), .premoveQueued(from: d2, to: Square("d4")))
    XCTAssertEqual(interaction.premove?.from, d2)
  }

  func test_givenOwnKnightThatMayBeTaken_whenPremovingPawn_thenRecaptureSquareOffered() {
    var session = GameSession()
    for m in ["e2e4", "e7e5", "g1f3", "d7d6", "d2d4", "c8g4"] { session.apply(uci: m) }
    session.apply(uci: "h2h3")  // Black to move; ...Bxf3 is coming, White premoves gxf3
    let targets = BoardInteraction.premoveTargets(from: Square("g2"), session: session)
    XCTAssertTrue(targets.contains(Square("f3")), "\(targets)")
    XCTAssertTrue(targets.contains(Square("g3")))
    XCTAssertTrue(targets.contains(Square("g4")))
  }

  func test_givenQueuedPremove_whenTappingAnywhereEmpty_thenPremoveCancelled() {
    var interaction = BoardInteraction()
    var session = GameSession()
    session.apply(uci: "e2e4")
    interaction.tap(d2, session: session, userColor: .white)
    interaction.tap(Square("d4"), session: session, userColor: .white)
    XCTAssertEqual(interaction.tap(Square("a5"), session: session, userColor: .white), .premoveCancelled)
    XCTAssertNil(interaction.premove)
  }

  func test_givenDragOfOwnPiece_whenDroppedOnTarget_thenMove() {
    var interaction = BoardInteraction()
    let session = GameSession()
    XCTAssertTrue(interaction.dragBegan(at: e2, session: session, userColor: .white))
    XCTAssertEqual(interaction.dragEnded(at: e4, session: session, userColor: .white), .move(from: e2, to: e4))
    XCTAssertNil(interaction.dragging)
  }

  func test_givenDragOfOpponentPiece_whenStarted_thenRefused() {
    var interaction = BoardInteraction()
    XCTAssertFalse(interaction.dragBegan(at: e7, session: GameSession(), userColor: .white))
  }

  func test_givenDrag_whenDroppedOffTarget_thenNoMoveAndPieceStaysSelected() {
    var interaction = BoardInteraction()
    let session = GameSession()
    interaction.dragBegan(at: e2, session: session, userColor: .white)
    XCTAssertEqual(interaction.dragEnded(at: e5, session: session, userColor: .white), .none)
    XCTAssertEqual(interaction.selected, e2)
  }

  func test_givenGameOver_whenTapping_thenNothing() {
    var interaction = BoardInteraction()
    var session = GameSession()
    session.resign(.black)
    XCTAssertEqual(interaction.tap(e2, session: session, userColor: .white), .none)
  }

  func test_givenUserArrows_whenSameArrowDrawnTwice_thenToggledOff() {
    var layer = AnnotationLayer()
    layer.toggleUserArrow(from: e2, to: e4)
    XCTAssertEqual(layer.userArrows.count, 1)
    layer.toggleUserArrow(from: e2, to: e4)
    XCTAssertTrue(layer.userArrows.isEmpty)
  }

  func test_givenUserSquareMark_whenToggledTwice_thenRemoved() {
    var layer = AnnotationLayer()
    layer.toggleUserArrow(from: e4, to: e4)
    XCTAssertEqual(layer.userCircles, [e4])
    layer.toggleUserArrow(from: e4, to: e4)
    XCTAssertTrue(layer.userCircles.isEmpty)
  }

  func test_givenSessionWithMoveAndCheck_whenHighlightsBuilt_thenLastMoveAndCheck() {
    var session = GameSession()
    for uci in ["e2e4", "f7f6", "d1h5"] { session.apply(uci: uci) }
    let highlights = BoardHighlights.make(session: session, ply: session.history.count, interaction: BoardInteraction())
    XCTAssertEqual(highlights.lastMove, [Square("d1"), Square("h5")])
    XCTAssertEqual(highlights.check, Square("e8"))
  }

  func test_givenBrowsingEarlierPly_whenHighlightsBuilt_thenThatPlysMoveAndNoSelection() {
    var session = GameSession()
    for uci in ["e2e4", "e7e5", "g1f3"] { session.apply(uci: uci) }
    let highlights = BoardHighlights.make(session: session, ply: 1, interaction: BoardInteraction())
    XCTAssertEqual(highlights.lastMove, [e2, e4])
  }

  func test_givenThemes_whenListed_thenGreenIsDefaultWithChessComColors() {
    XCTAssertEqual(BoardTheme.default.id, "sage")
    XCTAssertEqual(BoardTheme.green.light, 0xEEEED2)
    XCTAssertEqual(BoardTheme.green.dark, 0x769656)
    XCTAssertEqual(Set(BoardTheme.all.map(\.id)).count, BoardTheme.all.count)
  }

  func test_givenPieceSet_whenAssetNameAsked_thenSetSlashColorKind() {
    XCTAssertEqual(PieceSetID.staunty.assetName(color: .white, kind: .knight), "staunty/wN")
    XCTAssertEqual(PieceSetID.cburnett.assetName(color: .black, kind: .pawn), "cburnett/bP")
  }
}
