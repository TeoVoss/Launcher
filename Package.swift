// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Launcher",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        .target(
            name: "Launcher",
            dependencies: ["HotKey"],
            path: "Launcher"
        ),
        .testTarget(
            name: "LauncherTests",
            dependencies: ["Launcher"],
            path: "LauncherTests"
        )
    ]
) 