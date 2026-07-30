// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "birth",
    // zh-Hans is the product's source language: it is the resource
    // bundles' development region, so systems preferring neither zh-Hans
    // nor en fall back to Chinese. Both languages ship as full semantic-
    // key .strings tables; a missing key renders as the raw key, which
    // the key-set completeness test exists to prevent.
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BirthCore", targets: ["BirthCore"]),
        .executable(name: "Birth", targets: ["Birth"]),
    ],
    targets: [
        .target(
            name: "BirthCore",
            resources: [.process("Resources")]
        ),
        // The whole app lives in a library so its state/policy layer is
        // testable — SPM cannot attach tests to an executable target.
        .target(
            name: "BirthUI",
            dependencies: ["BirthCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Birth",
            dependencies: ["BirthUI"]
        ),
        .testTarget(
            name: "BirthCoreTests",
            dependencies: ["BirthCore"]
        ),
        .testTarget(
            name: "BirthUITests",
            dependencies: ["BirthUI"]
        ),
    ]
)
