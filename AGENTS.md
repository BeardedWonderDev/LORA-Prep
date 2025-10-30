# LoRA Prep Overview

LoRA Prep is a macOS-first toolkit that prepares LoRA training images. It ships both a SwiftPM CLI executable (`LoRAPrep`) and a SwiftUI desktop app; both surfaces share the same Vision/Core Image pipeline and should remain feature-parity replacements for the legacy `loraPrep.sh` script (which now serves as reference only).

# Repository Guidelines

## Key Paths
- `package/Package.swift` — SwiftPM manifest (macOS 13 minimum, executable + core library targets).
- `package/Sources/LORA-Prep/` — CLI entry point (`LORA_Prep.swift`).
- `package/Sources/LoRAPrepCore/` — Core image-processing pipeline (`LoRAPrepPipeline.swift` et al.).
- `package/CompiledModels/` — Bundled Core ML assets (e.g. `realesrgan512.mlmodelc`), optional at runtime.
- `package/loraPrep.sh` — Legacy zsh/Python workflow kept for behavior parity; do not extend.
- `app/LoraPrep/LoraPrep/` — SwiftUI macOS app implementation layered on the core library.
- `docs/` — UI planning/usage notes; review alongside this guide for context.

## Project Structure & Module Organization
Production CLI code sits in `Sources/LORA-Prep/LORA_Prep.swift` and the reusable core logic in `Sources/LoRAPrepCore`. `Package.swift` declares the `LoRAPrep` executable plus `LoRAPrepCore` library, targeting macOS 13 to guarantee Vision/Core Image availability. Treat `loraPrep.sh` as a parity reference only—migrate behavior into Swift rather than extending the embedded Python path. Keep generated `.build/` artifacts out of version control.

## Build, Test, and Development Commands
Use `swift build -c release` when you need the optimized binary; `swift run LoRAPrep -- --help` is the quickest way to confirm flag wiring during iteration. When validating the macOS app UI, run `xcodebuild -project app/LoraPrep/LoraPrep.xcodeproj -scheme LoraPrep -configuration Debug build` to mirror Xcode’s toolchain. The legacy automation still runs via `./loraPrep.sh`; set `DEBUG=1` in front of the command to surface its tracing and mirror tricky scenarios. Dependency resolution stays inside SwiftPM, so `swift package resolve` is the only supported install step.

Quick-start command sequence:
- `swift run LoRAPrep -- --help` — confirm CLI availability and flag wiring.
- `swift test` — execute the core pipeline test suite (`Tests/LoRAPrepCoreTests`).
- `xcodebuild -project app/LoraPrep/LoraPrep.xcodeproj -scheme LoraPrep -configuration Debug build` — ensure the macOS UI target compiles with Xcode’s toolchain.
- Optional: `DEBUG=1 ./loraPrep.sh` — compare legacy behavior when investigating regressions.

## Coding Style & Naming Conventions
Stick to four-space indentation, trailing commas where they clarify multi-line literals, and `// MARK:` dividers for major sections. Provide testable helper functions around Vision/Core Image calls and keep side effects at the CLI boundary. Introduce new flags in lower kebab-case (`--remove-background`) while backing properties remain camelCase. Reuse `normLoraName` for filename-safe tokens instead of reimplementing casing rules.

## Testing Guidelines
Create XCTest targets under `Tests/LoRAPrepTests` (none exist yet) and guard fixture sizes tightly to respect repository weight. Current coverage lives in `package/Tests/LoRAPrepCoreTests`; keep additions deterministic (pixel counts, bounding-box math, metadata assertions) over brittle image diffs. Always run `swift test` before requesting review, and document any new test assets or helper scripts alongside the suite.

## Commit & Pull Request Guidelines
Write imperative, present-tense subjects (`Add Vision rotation sampling`) and use bodies to note behavioral risks or macOS prerequisites. Reference the relevant issue, list the exact commands you executed (`swift run …`, `DEBUG=1 ./loraPrep.sh`), and share before/after crops when image output changes. Flag any changes that alter file naming, EXIF handling, or dependency expectations so reviewers can double-check them.

## Environment & Security Notes
The tool processes images locally; do not add network calls or cloud storage hooks. Preserve EXIF stripping by routing new outputs through `writePNG` (or a metadata-free equivalent), and avoid persisting user-provided source photos in the repository. If you touch the Vision segmentation path, confirm it still runs within macOS sandbox expectations and does not attempt to load external models. When working with super-resolution, note the default model bundle in `package/CompiledModels/` and ensure custom model paths are user-specified (`--superres-model` or via app settings).
