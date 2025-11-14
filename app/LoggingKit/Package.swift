// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LoggingKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LoggingKit",
            targets: ["LoggingKit"])
    ],
    targets: [
        .target(
            name: "LoggingKit"),
        .testTarget(
            name: "LoggingKitTests",
            dependencies: ["LoggingKit"])
    ],
    swiftLanguageVersions: [.v5]
)
