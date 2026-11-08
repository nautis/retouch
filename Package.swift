// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Retouch",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "RetouchCore"),
        .executableTarget(name: "Retouch", dependencies: ["RetouchCore"]),
        .executableTarget(name: "retouch-check", dependencies: ["RetouchCore"]),
    ]
)
