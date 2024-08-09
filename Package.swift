// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MoqLoc",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "MoqLoc",
            targets: ["MoqLoc"])
    ],
    dependencies: [
        .package(url: "git@github.com:RichLogan/QuicVarInt.git", branch: "temp"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.55.1"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MoqLoc",
            dependencies: [
                .product(name: "QuicVarInt", package: "QuicVarInt")
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "MoqLocTests",
            dependencies: ["MoqLoc"]),
    ]
)
