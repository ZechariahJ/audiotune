// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "audiotune",
    platforms: [
        .macOS("14.4") // Core Audio process-tap API requires macOS 14.4+
    ],
    targets: [
        .executableTarget(
            name: "audiotune",
            path: "Sources/audiotune"
        )
    ]
)
