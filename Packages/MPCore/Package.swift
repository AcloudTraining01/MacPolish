// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MPCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MPCore", targets: ["MPCore"])
    ],
    targets: [
        .target(name: "MPCore"),
        .testTarget(name: "MPCoreTests", dependencies: ["MPCore"])
    ]
)
