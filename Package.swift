// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoRAPrep",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LoRAPrep",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags(["-O"]) // optimize; this is image work
            ]
        )
    ]
)
