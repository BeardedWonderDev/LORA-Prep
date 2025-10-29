// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoRAPrep",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LoRAPrepCore", targets: ["LoRAPrepCore"]),
        .executable(name: "LoRAPrep", targets: ["LoRAPrep"])
    ],
    targets: [
        .target(
            name: "LoRAPrepCore",
            dependencies: []
        ),
        .executableTarget(
            name: "LoRAPrep",
            dependencies: ["LoRAPrepCore"],
            path: "Sources/LORA-Prep",
            swiftSettings: [
                .unsafeFlags(["-O"]) // optimize; this is image work
            ]
        ),
        .testTarget(
            name: "LoRAPrepCoreTests",
            dependencies: ["LoRAPrepCore"]
        )
    ]
)
