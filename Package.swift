// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TapoCam",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TapoCam", path: "Sources/TapoCam")
    ]
)
