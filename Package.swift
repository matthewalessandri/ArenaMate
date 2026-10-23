// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ArenaMateCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ArenaMateCore", targets: ["ArenaMateCore"])],
    targets: [
        .target(name: "ArenaMateCore", path: "Shared"),
        .testTarget(name: "ArenaMateCoreTests", dependencies: ["ArenaMateCore"], path: "Tests/ArenaMateCoreTests")
    ]
)
