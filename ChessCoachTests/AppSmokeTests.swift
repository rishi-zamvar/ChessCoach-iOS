import XCTest
import SwiftUI
@testable import ChessCoach

@MainActor
final class AppSmokeTests: XCTestCase {
    func test_givenApp_whenLaunched_thenRootViewBuilds() {
        let host = UIHostingController(rootView: RootView())
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
    }

    func test_givenBundle_whenLookingUpEngineNets_thenFilesArePresent() {
        XCTAssertNotNil(Bundle.main.url(forResource: "nn-1111cefa1111", withExtension: "nnue"))
        XCTAssertNotNil(Bundle.main.url(forResource: "maia-1100.pb", withExtension: "gz"))
        XCTAssertNotNil(Bundle.main.url(forResource: "move", withExtension: "wav"))
    }

    func test_givenPieceSets_whenRendered_thenEveryPieceDrawsPixels() throws {
        for set in ["staunty", "cardinal", "maestro", "cburnett"] {
            for color in ["w", "b"] {
                for kind in ["K", "Q", "R", "B", "N", "P"] {
                    let name = "\(set)/\(color)\(kind)"
                    let image = try XCTUnwrap(UIImage(named: name), name)
                    let fmt = UIGraphicsImageRendererFormat()
                    fmt.scale = 1
                    let cg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: fmt)
                        .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32)) }.cgImage)
                    let data = try XCTUnwrap(cg.dataProvider?.data as Data?)
                    // Alpha is one byte of every 4-byte pixel; any non-zero byte means something drew.
                    XCTAssertTrue(data.contains { $0 != 0 }, "\(name) rendered blank")
                }
            }
        }
    }
}
