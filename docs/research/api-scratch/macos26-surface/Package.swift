// swift-tools-version:6.0
// "What if we raise the app to macOS 26.0?" reference package.
//
// Deployment target is macOS 26.0 — NOT 27 — and everything in this target must
// compile with zero `#available` clutter except genuinely macOS-27-only APIs,
// which are guarded here on purpose so you can see exactly what they are.
//
// Build: swift build   (in this directory)
import PackageDescription

let package = Package(
    name: "Surface26",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .target(name: "Surface26", path: "Sources/Surface26")
    ],
    swiftLanguageModes: [.v5]
)
