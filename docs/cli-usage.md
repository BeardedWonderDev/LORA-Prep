# LoRAPrep CLI Usage

The `LoRAPrep` SwiftPM executable exposes the same pipeline used by the macOS app. Run it from the repository root with `swift run LoRAPrep -- <flags>`, or build a release binary via `swift build -c release` and execute the compiled product directly.

## Common Commands

- Show help and verify installation:
  ```bash
  swift run LoRAPrep -- --help
  ```
- Process a folder with transparent padding and background removal:
  ```bash
  swift run LoRAPrep -- \
    --input ~/Pictures/lora-set \
    --lora-name MyCharacter \
    --size 1024 \
    --remove-background \
    --pad-transparent
  ```
- Keep the full frame by padding instead of center cropping (new flag):
  ```bash
  swift run LoRAPrep -- \
    --input ~/Pictures/lora-set \
    --lora-name MyCharacter \
    --size 1024 \
    --pad-instead-of-crop
  ```
- Maximize the subject after background removal so it fills the target square:
  ```bash
  swift run LoRAPrep -- \
    --input ~/Pictures/lora-set \
    --lora-name MyCharacter \
    --size 1024 \
    --remove-background \
    --maximize-subject
  ```
- Run background removal with accurate Vision masks and extra edge control:
  ```bash
  swift run LoRAPrep -- \
    --input ~/Pictures/lora-set \
    --lora-name MyCharacter \
    --size 1024 \
    --remove-background \
    --segmentation-mode accurateVision \
    --mask-feather 1.5 \
    --mask-erosion 0.5
  ```

Processed images land beside the source folder in a directory named `processed-<normalized-name>-<timestamp>`. The CLI opens the output folder in Finder on completion.

## Flag Reference

- `--input <folder>` / `-i` — source directory containing images (required).
- `--lora-name <name>` / `-n` — display name used for output filenames (required).
- `--remove-background` / `-b` — apply Vision person segmentation to remove backgrounds.
- `--size <pixels>` / `-s` — target square dimension (default `1024`).
- `--superres-model <path>` — optional `.mlmodel` or `.mlmodelc` super-resolution bundle.
- `--pad-transparent` *(default)* — fill padding with transparency.
- `--pad-edge-color` — fill padding with sampled edge color.
- `--skip-face-detection` — bypass face detection, falling back to simple center cropping/padding.
- `--pad-instead-of-crop` — scale by the long edge and add padding rather than center-cropping when the source already exceeds the target size.
- `--maximize-subject` — after background removal (or when transparency exists), crop and scale the remaining subject to fill the frame without trimming it.
- `--segmentation-mode <automatic|accurateVision|deepLabV3|robustVideoMatting>` — choose the segmentation engine; non-Vision options fall back to Vision if their models are unavailable.
- `--mask-feather <pixels>` — Gaussian blur radius applied to the composed mask edges (default `0`).
- `--mask-erosion <pixels>` — morphology radius that tightens the mask before feathering (default `0`).
- `--help` / `-h` — print usage information.

> **Note:** Depth maps and portrait mattes remain embedded only when the photo stays in its original HEIC/Apple ProRAW container. Exporting as JPEG/PNG from Photos strips those attachments, so advanced mask fusion will rely solely on the Vision engine.

Set `DEBUG=1` before the command to increase log verbosity (`DEBUG=1 swift run LoRAPrep -- …`). For parity investigations, compare outputs with the legacy `./loraPrep.sh` script in the project root.
