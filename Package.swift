// swift-tools-version:5.9
// (Xcode15.0+)

import PackageDescription

let package = Package(
    name: "ElevenLabsComponents",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .macCatalyst(.v14),
        .visionOS(.v1),
        .tvOS(.v17),
    ],
    products: [
        .library(
            name: "ElevenLabsComponents",
            targets: ["ElevenLabsComponents"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.4.3"),
    ],
    targets: [
        .target(
            name: "ElevenLabsComponents",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift"),
            ],
            path: "Sources",
            resources: [
                .process("ElevenLabsComponents/UI/Visualizer/OrbShader.metal"),
            ]
        ),
        .testTarget(
            name: "ElevenLabsComponentsTests",
            dependencies: ["ElevenLabsComponents"]
        ),
    ],
    swiftLanguageVersions: [
        .v5,
    ]
)
