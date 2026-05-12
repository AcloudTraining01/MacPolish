// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MPHelperClient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MPHelperClient", targets: ["MPHelperClient"])
    ],
    dependencies: [
        .package(path: "../MPCore")
    ],
    targets: [
        .target(name: "MPHelperClient", dependencies: ["MPCore"]),
        .testTarget(name: "MPHelperClientTests", dependencies: ["MPHelperClient"])
    ]
)
