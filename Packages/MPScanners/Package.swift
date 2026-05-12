// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MPScanners",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MPScanners", targets: ["MPScanners"])
    ],
    dependencies: [
        .package(path: "../MPCore")
    ],
    targets: [
        .target(name: "MPScanners", dependencies: ["MPCore"]),
        .testTarget(name: "MPScannersTests", dependencies: ["MPScanners"])
    ]
)
