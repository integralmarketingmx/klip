// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Klip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Klip",
            path: "Sources/Klip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
