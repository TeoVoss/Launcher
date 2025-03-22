// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Launcher",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.1.2")
    ],
    targets: [
        .target(
            name: "Launcher",
            dependencies: ["HotKey", "Highlightr"],
            path: "Launcher"
        ),
        .testTarget(
            name: "LauncherTests",
            dependencies: ["Launcher"],
            path: "LauncherTests"
        )
    ]
)