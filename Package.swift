// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Mocker",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)],
    products: [
        .library(name: "Mocker", targets: ["Mocker"]),
        .library(name: "MockerXCTest", targets: ["MockerXCTest"]),
        .library(name: "MockerTesting", targets: ["MockerTesting"])
    ],
    targets: [
        .target(
            name: "Mocker"
        ),
        .target(name: "MockerXCTest", dependencies: ["Mocker"]),
        .target(name: "MockerTesting", dependencies: ["Mocker"]),
        .testTarget(
            name: "MockerTests",
            dependencies: ["Mocker", "MockerXCTest", "MockerTesting"],
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v6])
