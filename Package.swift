// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DnDCategoriser",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DnDCategoriser",
            path: "Sources/DnDCategoriser",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DnDCategoriserTests",
            dependencies: ["DnDCategoriser"],
            path: "Tests/DnDCategoriserTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
