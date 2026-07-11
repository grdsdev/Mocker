// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Mocker",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v11),
        .tvOS(.v12),
        .watchOS(.v6)],
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
    swiftLanguageVersions: [.v5])
