// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MPUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MPUI", targets: ["MPUI"])
    ],
    dependencies: [
        .package(path: "../MPCore")
    ],
    targets: [
        .target(name: "MPUI", dependencies: ["MPCore"]),
        .testTarget(name: "MPUITests", dependencies: ["MPUI"])
    ]
)
