// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HARLens",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HARCore", targets: ["HARCore"]),
        .executable(name: "HARLens", targets: ["HARLens"])
    ],
    targets: [
        .target(name: "HARCore"),
        .executableTarget(name: "HARLens", dependencies: ["HARCore"], path: "Sources/HARLens"),
        .testTarget(name: "HARCoreTests", dependencies: ["HARCore"]),
        .testTarget(name: "HARLensTests", dependencies: ["HARLens"], path: "Tests/HARLensTests")
    ]
)
