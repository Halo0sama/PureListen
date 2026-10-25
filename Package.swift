// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PureListen",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "PureListenCore",
            path: "Sources/PureListenCore"
        ),
        .executableTarget(
            name: "PureListen",
            dependencies: ["PureListenCore"],
            path: "Sources/PureListen"
        ),
        .executableTarget(
            name: "hogtest",
            dependencies: ["PureListenCore"],
            path: "Sources/hogtest"
        ),
        .executableTarget(
            name: "apitest",
            dependencies: ["PureListenCore"],
            path: "Sources/apitest"
        ),
    ],
    swiftLanguageModes: [.v5]
)
