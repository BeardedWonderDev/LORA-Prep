# Repository Guidelines

## Project Structure & Module Organization
Production code sits in `Sources/LORA-Prep/LORA_Prep.swift`; there are no secondary modules yet. `Package.swift` declares a single executable (`LoRAPrep`) targeting macOS 13 to guarantee Vision and Core Image availability. Treat `loraPrep.sh` as a parity reference only—migrate behavior into Swift rather than extending the embedded Python path. Keep generated `.build/` artifacts out of version control.

## Build, Test, and Development Commands
Use `swift build -c release` when you need the optimized binary; `swift run LoRAPrep -- --help` is the quickest way to confirm flag wiring during iteration. When validating the macOS app UI, run `xcodebuild -project app/LoraPrep/LoraPrep.xcodeproj -scheme LoraPrep -configuration Debug build` to mirror Xcode’s toolchain. The legacy automation still runs via `./loraPrep.sh`; set `DEBUG=1` in front of the command to surface its tracing and mirror tricky scenarios. Dependency resolution stays inside SwiftPM, so `swift package resolve` is the only supported install step.

## Coding Style & Naming Conventions
Stick to four-space indentation, trailing commas where they clarify multi-line literals, and `// MARK:` dividers for major sections. Provide testable helper functions around Vision/Core Image calls and keep side effects at the CLI boundary. Introduce new flags in lower kebab-case (`--remove-background`) while backing properties remain camelCase. Reuse `normLoraName` for filename-safe tokens instead of reimplementing casing rules.

## Testing Guidelines
Create XCTest targets under `Tests/LoRAPrepTests` (none exist yet) and guard fixture sizes tightly to respect repository weight. Prefer deterministic checks—pixel counts, bounding-box math, metadata assertions—over full-image diffs prone to precision noise. Always run `swift test` before requesting review, and document any new test assets or helper scripts alongside the suite.

## Commit & Pull Request Guidelines
Write imperative, present-tense subjects (`Add Vision rotation sampling`) and use bodies to note behavioral risks or macOS prerequisites. Reference the relevant issue, list the exact commands you executed (`swift run …`, `DEBUG=1 ./loraPrep.sh`), and share before/after crops when image output changes. Flag any changes that alter file naming, EXIF handling, or dependency expectations so reviewers can double-check them.

## Environment & Security Notes
The tool processes images locally; do not add network calls or cloud storage hooks. Preserve EXIF stripping by routing new outputs through `writePNG` (or a metadata-free equivalent), and avoid persisting user-provided source photos in the repository. If you touch the Vision segmentation path, confirm it still runs within macOS sandbox expectations and does not attempt to load external models.
