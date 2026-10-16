import ChessCoachKit
import XCTest
@testable import ChessCoach

final class ServerLinkTests: XCTestCase {
  func test_givenResolvedAddresses_whenCheckedForTailnet_thenOnlyPinnedPCAddressesPass() {
    XCTAssertTrue(ServerLink.isTailnet(["100.91.236.115"]))
    XCTAssertTrue(ServerLink.isTailnet(["fd7a:115c:a1e0::1234", "100.91.236.115"]))
    XCTAssertFalse(ServerLink.isTailnet([]))
    XCTAssertFalse(ServerLink.isTailnet(["192.168.1.50"]))
    XCTAssertFalse(ServerLink.isTailnet(["100.91.236.115", "203.0.113.9"]), "a spoofed extra address must be rejected")
  }

  func test_givenM5JobResult_whenParsed_thenPositionsWithCpAndMateLines() throws {
    let json = """
      {"positions": [
        {"fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
         "lines": [{"multipv": 1, "depth": 22, "cp": 25, "pv": ["e2e4", "e7e5"]},
                   {"multipv": 2, "depth": 22, "cp": 18, "pv": ["d2d4"]}]},
        {"fen": "x", "lines": [{"multipv": 1, "depth": 22, "mate": -2, "pv": ["a2a3"]}]},
        {"fen": "y", "lines": []}
      ]}
      """
    let result = try JSONDecoder().decode(JSON.self, from: Data(json.utf8))
    let positions = ServerLink.parsePositions(result)
    XCTAssertEqual(positions.count, 2)
    XCTAssertEqual(positions[0].lines.map(\.score), [.centipawns(25), .centipawns(18)])
    XCTAssertEqual(positions[1].lines.first?.score, .mate(-2))
    XCTAssertEqual(positions[0].lines.first?.depth, 22)
  }
}
