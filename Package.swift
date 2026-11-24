// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DroidMirror",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DroidMirror",
            path: "Sources/DroidMirror",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
            ]
        )
    ]
)
