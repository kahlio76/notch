// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchCore"),
        .executableTarget(name: "Notch", dependencies: ["NotchCore"]),
        .executableTarget(name: "notch-hook"),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
    ]
)
