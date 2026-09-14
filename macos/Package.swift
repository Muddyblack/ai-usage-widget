// swift-tools-version:5.9
import PackageDescription

// The macOS frontend. An ordinary SwiftPM executable rather than an Xcode
// project, so the whole build stays in text files: scripts/build-app.sh wraps
// the product in `AI Usage.app` with its Info.plist, the compiled asset
// catalog and the frozen Python backend beside it.
let package = Package(
    name: "AIUsage",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AIUsage", path: "Sources/AIUsage"),
        // The parts with no AppKit in them: decoding the contract, replaying
        // quota resets, formatting a countdown, and not losing a Linux
        // frontend's settings on save. Everything visual is proved by
        // --selftest and the screenshots instead.
        .testTarget(name: "AIUsageTests", dependencies: ["AIUsage"], path: "Tests/AIUsageTests"),
    ]
)
