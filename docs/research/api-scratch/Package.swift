// swift-tools-version:6.0
// Scratch package for the PureListen SDK/API scout task (task-2).
//
// Goal: prove every API recommended in docs/research/sdk-api-cheatsheet.md
// actually compiles against the real macOS 27.0 SDK on this machine.
//
// Notes:
// * tools-version is deliberately kept at 6.0 to match the app's own
//   Package.swift. PackageDescription's `.macOS(.v27)` symbol requires
//   tools-version 6.4, so the deployment target is expressed with the
//   string form `.macOS("27.0")`, which SwiftPM accepts since 5.x.
// * `.macOS("26.0")` / `.macOS("27.0")` in a tools-6.0 manifest both work;
//   see docs/research/sdk-api-cheatsheet.md §0 for the deployment-target
//   decision table.
// * swiftLanguageModes: [.v5] mirrors the app (Swift 6 compiler, Swift 5
//   language mode), so snippets are drop-in for the current target.
import PackageDescription

let package = Package(
    name: "APIScratch",
    platforms: [
        .macOS("27.0")
    ],
    targets: [
        .target(
            name: "APIScratch",
            path: "Sources/APIScratch"
        )
    ],
    swiftLanguageModes: [.v5]
)
