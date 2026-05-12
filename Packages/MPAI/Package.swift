// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MPAI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MPAI", targets: ["MPAI"])
    ],
    dependencies: [
        .package(path: "../MPCore")
    ],
    targets: [
        .target(name: "MPAI", dependencies: ["MPCore"]),
        .testTarget(name: "MPAITests", dependencies: ["MPAI"])
    ]
)
