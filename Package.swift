// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PrimsPaste",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PrimsPasteCore", targets: ["PrimsPasteCore"]),
        .executable(name: "PrimsPaste", targets: ["PrimsPaste"]),
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
        .testTarget(
            name: "PrimsPasteCoreTests",
            dependencies: ["PrimsPasteCore"],
            path: "Tests/PrimsPasteCoreTests"
        ),
    ]
)
