// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FlagsmithOpenFeatureProvider",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15),
    ],
    products: [
        .library(name: "FlagsmithOpenFeature", targets: ["FlagsmithOpenFeature"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-feature/swift-sdk.git", from: "0.6.0"),
        .package(url: "https://github.com/Flagsmith/flagsmith-ios-client.git", from: "3.10.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.27.1"),
    ],
    targets: [
        .target(
            name: "FlagsmithOpenFeature",
            dependencies: [
                .product(name: "OpenFeature", package: "swift-sdk"),
                .product(name: "FlagsmithClient", package: "flagsmith-ios-client"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "FlagsmithOpenFeatureTestSupport",
            dependencies: [.product(name: "Logging", package: "swift-log")],
            path: "tests/support"
        ),
        .testTarget(
            name: "FlagsmithOpenFeatureTests",
            dependencies: ["FlagsmithOpenFeature", "FlagsmithOpenFeatureTestSupport"],
            path: "tests/unit"
        ),
        .testTarget(
            name: "FlagsmithOpenFeatureIntegrationTests",
            dependencies: [
                "FlagsmithOpenFeature",
                "FlagsmithOpenFeatureTestSupport",
                .product(name: "FlyingFox", package: "FlyingFox"),
            ],
            path: "tests/integration"
        ),
    ]
)
