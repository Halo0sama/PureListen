// swift-tools-version:6.0
// Guarded-reference package for the PureListen SDK/API scout task (task-2).
//
// This package deliberately mirrors the APP's current manifest:
//   * swift-tools-version 6.0
//   * platforms: [.macOS(.v13)]      ← the app today
//   * swiftLanguageModes: [.v5]
//
// It proves the exact `#available` guard patterns required to use the
// macOS 14 / 15 / 26 / 27 APIs recommended in
// docs/research/sdk-api-cheatsheet.md while keeping deployment at macOS 13.
//
// Build:  swift build          (in this directory)
import PackageDescription

let package = Package(
    name: "GuardedUI",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "GuardedUI",
            path: "Sources/GuardedUI"
        )
    ],
    swiftLanguageModes: [.v5]
)
