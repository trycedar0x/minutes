// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperDiarize",
    platforms: [.macOS(.v14)],
    targets: [
        // Core library — pure logic, no UI, fully testable
        .target(
            name: "WhisperDiarizeCore",
            path: "Sources/WhisperDiarizeCore"
        ),

        // Main app — UI layer, depends on Core
        .executableTarget(
            name: "WhisperDiarize",
            dependencies: ["WhisperDiarizeCore"],
            path: "Sources/WhisperDiarize",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/transcribe.py"),
                .copy("Resources/pyproject.toml"),
                .copy("Resources/uv.lock"),
            ]
        ),

        // Unit tests — run with: swift test
        .testTarget(
            name: "WhisperDiarizeTests",
            dependencies: ["WhisperDiarizeCore"],
            path: "Tests/WhisperDiarizeTests"
        ),

        // UI tests — run with: xcodebuild test (open Package.swift in Xcode first)
        .testTarget(
            name: "WhisperDiarizeUITests",
            dependencies: [],
            path: "UITests/WhisperDiarizeUITests"
        ),
    ]
)
