// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "ChessCoachKit",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "ChessCoachKit", targets: ["ChessCoachKit"])
  ],
  dependencies: [
    .package(url: "https://github.com/chesskit-app/chesskit-swift", from: "0.17.0"),
    .package(url: "https://github.com/chesskit-app/chesskit-engine", from: "0.7.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    // FSRS-6 spaced repetition (MIT). No tagged releases; pinned.
    .package(url: "https://github.com/open-spaced-repetition/swift-fsrs", revision: "4fbaf20"),
  ],
  targets: [
    .target(
      name: "ChessCoachKit",
      dependencies: [
        .product(name: "ChessKit", package: "chesskit-swift"),
        .product(name: "ChessKitEngine", package: "chesskit-engine"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "FSRS", package: "swift-fsrs"),
      ],
      resources: [.copy("Resources/openings.tsv"), .copy("Resources/curriculum.json")]
    ),
    .testTarget(
      name: "ChessCoachKitTests",
      dependencies: ["ChessCoachKit"]
    ),
  ]
)
