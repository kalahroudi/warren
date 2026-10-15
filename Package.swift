// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "Warren",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WarrenCore", targets: ["WarrenCore"]),
        .executable(name: "WarrenApp", targets: ["WarrenApp"]),
        .executable(name: "warrend", targets: ["WarrenDaemon"]),
        .executable(name: "warren", targets: ["WarrenCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.5"),
    ],
    targets: [
        .target(name: "WarrenCore", dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]),
        .executableTarget(name: "WarrenApp", dependencies: ["WarrenCore"]),
        .executableTarget(name: "WarrenDaemon", dependencies: ["WarrenCore"]),
        .executableTarget(name: "WarrenCLI", dependencies: ["WarrenCore"]),
        .testTarget(name: "WarrenCoreTests", dependencies: ["WarrenCore"]),
    ]
)
