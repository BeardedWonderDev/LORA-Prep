# AGENTS.md — Guidance for Codex CLI

> **Project**: **LoRAPrep** — face‑aware dataset preprocessing for LoRA training (Swift CLI)
> **Platform**: macOS 13+ (Ventura), SwiftPM, Vision + Core Image

---

## Current state (Swift CLI)
- **Binary**: Swift Package executable: `LoRAPrep`
- **Entry**: `Sources/LORA-Prep/LORA_Prep.swift`
- **Functionality**:
  - Input: top‑level images in a folder (jpg/jpeg/png/heic/tif/tiff/webp)
  - Output: `processed-<LORA_NAME>-<TIMESTAMP>/NN_<LORA_NAME>.png` (1024×1024, EXIF‑free)
  - **Face path**: Vision face rectangles → size/edge filters → square around face (`marginK=1.9`) → min/max side clamps → pad if needed → resize
  - **No‑face path**: scale long side to 1024 → if both dims ≥ 1024 center‑crop else center‑pad
  - Padding color: **edge‑average** (bands along all four borders)
  - Background removal: optional Vision person segmentation (`--remove-background`) producing alpha
  - Logs: `FACE_FOUND …` or `NO_FACE …` with sizes/bboxes

### CLI usage
```bash
swift build -c release
.build/release/LoRAPrep \
  --input "/path/to/folder" \
  --lora-name "LORA_NAME" \
  [--remove-background] \
  [--size 1024]
```

---

## Legacy reference (parity target)
The original Automator/zsh pipeline embedded a Python helper using **OpenCV** cascades.

**Behavioral highlights we aim to match:**
- Multi‑cascade detection: `frontal_default`, `frontal_alt2`, `frontal_alt`, `profile`
- Param sweeps (`scaleFactor` 1.05/1.10; `minNeighbors` 3/5)
- **Voting** by IOU ≥ 0.35 requiring ≥ 2 supports
- Sanity filters: face area in `[6%, 60%]` of image; **edge‑guard** 4%
- Eye check for frontal candidates (≥1 eye inside ROI)
- Square margin ≈ 1.9× face max(w,h) + min/max side clamps
- Edge‑average padding color

File in repo for reference: `loraPrep.sh` (don’t re‑enable; it’s the parity oracle).

---

## Repository map
```
Sources/
  LORA-Prep/
    LORA_Prep.swift      # Swift CLI main (Vision + Core Image)
loraPrep.sh              # Legacy zsh + embedded Python (parity reference)
AGENTS.md                # This file
Package.swift            # SwiftPM config
```

---

## Conventions & guardrails
- **Language**: Swift 5.9+, SwiftPM, no third‑party Swift deps
- **APIs**: Vision (face rectangles, optional landmarks/segmentation), Core Image
- **Safety**: never introduce network calls or external services for image ops
- **Diff style**: smallest possible change set per task; keep functions pure/testable
- **Logs**: prefer `print` gated by flags; do not spam in non‑debug runs
- **EXIF**: always write clean PNGs; do not preserve metadata

---

## What Codex should do next (roadmap)
**P1 — Detection parity**
1. **Rotate–detect–union**: run face detection at rotations −15°, 0°, +15°; map boxes back; union by IOU ≥ 0.35; then apply existing size/edge filters; pick best.
2. **Optional landmarks check**: for frontal‑looking boxes, run `VNDetectFaceLandmarksRequest` and require at least one eye or nose landmark; skip for clear profiles.

**P2 — Preprocess + thresholds**
3. Add optional luminance equalization/contrast boost before detection (Core Image) behind a flag.
4. Expose thresholds as CLI flags with sane defaults:
   - `--min-face-frac` (default 0.06)
   - `--max-face-frac` (default 0.60)
   - `--edge-guard`    (default 0.04)
   - `--margin-k`      (default 1.90)
   - `--max-side-k`    (default 1.10)

**P3 — Background modes & overlays**
5. `--bg` option: `none|alpha|blur|#RRGGBB` (alpha uses Vision mask; blur/hex composites result over background).
6. `--debug-overlays`: write side‑by‑side annotated PNGs (original + boxes + chosen square + pad areas) for quick visual QA.

**P4 — Tests/fixtures**
7. Add `Tests/LoRAPrepTests` with a small fixture set (frontal/profile/non‑face/edge cases) and snapshot checks (tolerance‑based).

Acceptance for parity: face images centered with full headroom like the Python path; non‑face images never take face path; outputs 1024×1024 PNGs named and EXIF‑clean.

---

## Commands Codex can run
- Build: `swift build -c release`
- Run: `.build/release/LoRAPrep --input "…" --lora-name "…" [--remove-background] [--size 1024]`
- Format/lint: (none enforced yet)
- Tests: (to be added under `Tests/`)

> **Note**: Do not introduce brew/pip steps. Keep the tool self‑contained.

---

## Things to avoid
- Adding external Swift packages
- Introducing Python/OpenCV back into the Swift pipeline
- Network calls for background removal
- Huge refactors spanning multiple concerns in one patch