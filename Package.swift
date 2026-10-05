// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockShift",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DockShift",
            path: "Sources/DockShift",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
