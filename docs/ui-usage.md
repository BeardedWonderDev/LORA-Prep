# LoRAPrep macOS UI Usage

The `LoraPrep` SwiftUI app wraps the shared `LoRAPrepCore` pipeline with a desktop interface that exposes every command-line flag and adds an in-app results browser.

## Launch & Configuration

1. Build and run the Xcode project at `app/LoraPrep/LoraPrep.xcodeproj`.
2. Choose **Select Folder…** to pick the training photo directory (top-level images only).
3. Enter a LoRA name. The sidebar shows the normalized token that will be used in filenames.
4. Adjust options:
   - Output size (512–2048 px).
   - Background removal toggle (Vision segmentation, macOS 12+).
   - Padding mode (transparent vs. edge color), face-detection bypass, and optional Core ML super-resolution model (`.mlmodel`/`.mlmodelc`).
5. Press **Process Images** to start the pipeline. Progress appears inline; the button disables until processing finishes.

## Results Browser

- Processed runs appear in the lower pane. Each row shows the original image beside the generated PNG (160×160 previews).
- Buttons beneath each preview reveal that specific file in Finder.
- A persistent **Reveal Output Folder** button opens the containing directory for manual inspection.
- Failures are summarized below the gallery with filenames and error messages.

## Manual Test Checklist

- ✅ CLI compatibility: `swift run LoRAPrep -- --help` and padding behavior confirmed via unit tests (`swift test`).
- ✅ UI launch/build: Xcode project links `LoRAPrepCore` (add via **File ▸ Add Packages…** pointing to the repo root).
- ✅ Folder selection & validation: empty selections prompt inline error; LoRA name normalization surfaces in UI.
- ✅ Processing flow: run with background removal on/off, transparency vs. edge-color padding, skip-face-detection toggled.
- ✅ Optional super-resolution: selecting `.mlmodelc` loads successfully; clearing the selection resets state.
- ✅ Results review: side-by-side thumbnails display, Finder reveal works for both originals and processed outputs, failure callouts list any errors.

Document the specific sample folders and models used during testing alongside screenshots when preparing PRs, per `AGENTS.md` guidance.
