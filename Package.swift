// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PrimsPaste",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PrimsPasteCore", targets: ["PrimsPasteCore"]),
        .executable(name: "PrimsPaste", targets: ["PrimsPaste"]),
        .executable(name: "prims-paste", targets: ["PrimsPasteCLI"]),
    ],
    targets: [
        .target(
            name: "PrimsPasteCore",
            path: "Sources/PrimsPasteCore",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "PrimsPaste",
            dependencies: ["PrimsPasteCore"],
            path: "Sources/PrimsPaste",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("CryptoKit"),
            ]
        ),
        .executableTarget(
            name: "PrimsPasteCLI",
            dependencies: ["PrimsPasteCore"],
            path: "Sources/PrimsPasteCLI",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "PrimsPasteCoreTests",
            dependencies: ["PrimsPasteCore"],
            path: "Tests/PrimsPasteCoreTests",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
