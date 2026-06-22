// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Klip",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Pinned to 0.18.x: WhisperKit is pre-1.0, so any 0.x bump can break the API. Bump deliberately.
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMinor(from: "0.18.0"))
    ],
    targets: [
        .executableTarget(
            name: "Klip",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/Klip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
