# LoRAPrep macOS UI Migration Plan

This document breaks down the work required to turn the Swift CLI pipeline into a graphical macOS app using the existing Xcode project under `app/LoraPrep`.

## 1. Share Core Pipeline Logic

1. Create a new SwiftPM target named `LoRAPrepCore`.
   - Move CLI-independent code from `Sources/LORA-Prep/LORA_Prep.swift:62-520` (image IO, detection helpers, `Pipeline`) into `Sources/LoRAPrepCore/Pipeline.swift`.
   - Leave `Args`, Finder interactions, and `CommandLine` handling in the original executable target.
2. Add `LoRAPrepCore` to `Package.swift`, keeping dependencies on AppKit, Vision, CoreImage, CoreML, ImageIO, UniformTypeIdentifiers.
3. Expose an API such as:
   ```swift
   public struct LoRAPrepConfiguration { ... }
   public struct ProcessedImagePair { let original: URL; let processed: URL }
   public final class LoRAPrepPipeline {
       public init(configuration: LoRAPrepConfiguration)
       public func run(progress: @escaping (ProgressUpdate) -> Void) throws -> [ProcessedImagePair]
   }
   ```
4. Confirm CLI builds/runs: `swift build`, `swift run LoRAPrep -- --help`, followed by a sample processing run.

## 2. Extend Configuration Surface

1. Add toggles to `LoRAPrepConfiguration` for behaviors only available in the legacy script:
   - `padWithTransparency` (default `true`, but allows colored padding).
   - `skipFaceDetection` (default `false` to match CLI).
   - `preferPaddingOverCrop` (default `false`, lets users retain the full frame with padded borders instead of center-cropping).
2. Update shared pipeline functions to respect these toggles (reusing existing helper code from `loraPrep.sh` where necessary).
3. Create `Tests/LoRAPrepCoreTests/PipelineConfigTests.swift` covering padding mode and face-detection bypass scenarios with deterministic CIImage fixtures.
4. Run `swift test`.

## 3. Hook CLI Executable to Shared Module

1. Replace direct pipeline logic in `Sources/LORA-Prep/LORA_Prep.swift` with calls into `LoRAPrepPipeline`.
2. Preserve CLI UX: Finder reveal on completion, identical log output, existing flags.
3. Manual test: `swift run LoRAPrep -- --input <folder> --lora-name Sample`.

## 4. Prepare Xcode Project for Shared Code

1. In `app/LoraPrep/LoraPrep.xcodeproj`, add the SwiftPM package referencing the workspace root.
2. Link the `LoraPrep` app target against `LoRAPrepCore`.
3. Remove placeholder SwiftUI logic now superseded by the shared pipeline.
4. Build the Xcode project to confirm linkage.

## 5. Define SwiftUI App Architecture

1. Add `AppState` (`ObservableObject`) under `app/LoraPrep/LoraPrep/State/AppState.swift` with published properties:
   - Configuration: `inputFolder`, `superResModel`, `loraName`, `size`, `removeBackground`, `padWithTransparency`, `skipFaceDetection`.
   - Processing status: `isProcessing`, `progress`, `error`, `results`.
2. Introduce `ResultPair` model representing original/processed URLs plus cached thumbnails.
3. Add validation helpers (e.g., derived `var isReadyToProcess: Bool`).
4. Smoke test via SwiftUI previews.

## 6. Implement Input Controls

1. Create `InputControlsView`:
   - Folder picker (`NSOpenPanel`) with selected path display.
   - `TextField` for LoRA name applying `normLoraName`.
   - Slider + stepper for size (512–2048) with live label.
   - Toggle for `removeBackground` (gated on macOS 12 availability).
   - File picker for super-resolution model filtering `.mlmodel`/`.mlmodelc`.
   - Toggles for `padWithTransparency`, `skipFaceDetection`, and `preferPaddingOverCrop`.
2. Wire controls to `AppState` bindings.
3. Manual test: run app, confirm controls update state as expected.

## 7. Orchestrate Processing

1. Add `ProcessButton` to kick off work:
   - Disable controls when `isProcessing`.
   - Dispatch pipeline on a background queue with progress closure updating `AppState.progress`.
   - Collect `ProcessedImagePair` and populate `results`.
   - Store disk outputs in the same directory structure as CLI.
2. Provide cancellation hook for future improvement (optional).
3. Manual test: execute end-to-end run on sample folder; ensure progress indicator updates.

## 8. Build Results Browser

1. Implement `ResultsView` showing `results` as side-by-side thumbnails (original vs processed).
   - Use `LazyVGrid` or list with `ProcessedImageRow`.
   - Include metadata (dimensions, processing timestamp, face detection outcome if available).
   - Offer buttons for “Reveal in Finder” and “Quick Look”.
2. Add detail view with full-size comparison using `GeometryReader` and zoom controls.
3. Manual test: verify rows populate after processing, links open Finder/Quick Look correctly.

## 9. Completion & Error UX

1. Replace automatic Finder reveal with an in-app banner summarizing counts and run duration.
2. Provide optional “Open Output Folder” button to mirror old behavior.
3. Surface errors via `Alert` or inline error presentation with retry guidance.
4. Manual test: simulate missing input or invalid model to confirm alert flow.

## 10. Final QA

1. Run `swift test` and build both CLI and app targets.
2. Perform manual scenarios:
   - Run with/without super-resolution model.
   - Toggle background removal and padding modes.
   - Use skip-face-detection mode for edge cases.
3. Update documentation (`AGENTS.md` or README replacement) summarizing new UI workflow and test steps.
