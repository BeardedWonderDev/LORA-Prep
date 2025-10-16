#!/bin/zsh
set -euo pipefail

# -------- DEBUG SWITCH --------
DEBUG=${DEBUG:-0}
[[ "$DEBUG" = "1" ]] && set -x
trap 'code=$?; echo "[FATAL] Script aborted at line $LINENO (exit $code)"; exit $code' ERR
log() { echo "[$(date +%H:%M:%S)] $*"; }

# ===== Pin Python + cv2 for Homebrew OpenCV (3.13) =====
PYTHON_BIN="/opt/homebrew/opt/python@3.13/bin/python3.13"
CV2_ROOT="/opt/homebrew/Cellar/opencv/4.12.0_12/lib/python3.13/site-packages"
CV2_NESTED="${CV2_ROOT}/cv2/python-3.13"
export PYTHONPATH="${CV2_ROOT}:${CV2_NESTED}:${PYTHONPATH:-}"
export OPENCV_LOG_LEVEL=ERROR

# Prefer face-aware path (requires python3.13 + opencv + pillow present)
FACE_AWARE=${FACE_AWARE:-1}

# -------- PROMPTS --------
SRC_DIR=$(osascript -e 'POSIX path of (choose folder with prompt "Select the folder containing your training photos")') || exit 1
LORA_NAME_RAW=$(osascript -e 'text returned of (display dialog "Enter your LoRA name (used in filenames):" default answer "")') || exit 1

# normalize LoRA token for filenames
LORA_NAME=$(echo "$LORA_NAME_RAW" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9 _-]+//g; s/[[:space:]]+/_/g; s/^_+|_+$//g')
if [[ -z "$LORA_NAME" ]]; then
  osascript -e 'display alert "LoRA name cannot be empty." as critical buttons {"OK"} default button "OK"'
  exit 1
fi

# -------- OUTPUT FOLDER --------
STAMP=$(date +"%Y%m%d-%H%M%S")
PROC_DIR="${SRC_DIR%/}/processed-${LORA_NAME}-${STAMP}"
TMP_DIR="${PROC_DIR}/.tmp"
mkdir -p "$PROC_DIR" "$TMP_DIR"
log "Output: $PROC_DIR"

# -------- COPY IMAGES --------
typeset -a exts
exts=(jpg jpeg png heic tiff tif webp)
found_any=false
for ext in $exts; do
  while IFS= read -r -d '' f; do
    cp -p "$f" "$PROC_DIR/"
    found_any=true
  done < <(find "$SRC_DIR" -maxdepth 1 -type f -iname "*.${ext}" -print0)
done
if [[ "$found_any" = false ]]; then
  osascript -e 'display alert "No images found at the top level of that folder." message "Supported: JPG, JPEG, PNG, HEIC, TIFF, WEBP" as warning buttons {"OK"} default button "OK"'
  exit 1
fi

# -------- exiftool (Homebrew formula) --------
EXIFTOOL="$(command -v exiftool || true)"
if [[ -z "$EXIFTOOL" ]]; then
  for p in /opt/homebrew/bin/exiftool /usr/local/bin/exiftool ; do
    [[ -x "$p" ]] && EXIFTOOL="$p" && break
  done
fi
[[ -n "$EXIFTOOL" ]] && log "Using exiftool at: $EXIFTOOL" || log "exiftool not available; will only clear xattrs (not full EXIF wipe)."

# --- embed face_crop.py (heredoc) ---
FACEPY="${TMP_DIR}/face_crop.py"
cat > "$FACEPY" <<'PYEOF'
#!/usr/bin/env python3
import os, sys
from pathlib import Path
import numpy as np
import cv2
from PIL import Image

# Usage: face_crop.py <input> <output> [size]
# Returns 0 on success (even if no face). Returns 2 on fatal error.

DEBUG = os.environ.get("FACE_DEBUG") in ("1","true","TRUE","yes","YES")
def dlog(*a):
    if DEBUG: print(*a, file=sys.stderr, flush=True)

# ---- tunables ----
MIN_FACE_FRAC = 0.06   # reject faces smaller than 6% of image area
MAX_FACE_FRAC = 0.60   # reject faces larger than 60% of image area
SUPPORT_N     = 2      # require at least 2 overlapping detections
IOU_THRESH    = 0.35   # overlap for “same face”
EDGE_GUARD    = 0.04   # reject boxes whose center is too close to edge
MARGIN_K      = 1.90   # margin around the chosen face (× max(w,h))

def edge_avg_color(arr, border_frac=0.04):
    h, w = arr.shape[:2]
    bw = max(1, int(min(h, w) * border_frac))
    top    = arr[0:bw, :, :]
    bottom = arr[h-bw:h, :, :]
    left   = arr[:, 0:bw, :]
    right  = arr[:, w-bw:w, :]
    edges  = np.concatenate([top.reshape(-1,3), bottom.reshape(-1,3),
                             left.reshape(-1,3), right.reshape(-1,3)], axis=0)
    mean = edges.mean(axis=0)
    return tuple(int(x) for x in mean.tolist())

def paste_with_padding(img_rgb, box, side, pad_color):
    h, w = img_rgb.shape[:2]
    x1, y1, x2, y2 = box
    sx1, sy1 = max(0, x1), max(0, y1)
    sx2, sy2 = min(w, x2), min(h, y2)
    canvas = np.full((side, side, 3), pad_color, dtype=np.uint8)
    if sx2 > sx1 and sy2 > sy1:
        crop = img_rgb[sy1:sy2, sx1:sx2, :]
        offx = max(0, -x1)
        offy = max(0, -y1)
        tx2 = min(side, offx + crop.shape[1])
        ty2 = min(side, offy + crop.shape[0])
        canvas[offy:ty2, offx:tx2] = crop[0:ty2-offy, 0:tx2-offx]
    return canvas

def resize_long_side_to(img_rgb, target=1024):
    h, w = img_rgb.shape[:2]
    long_side = max(w, h)
    if long_side == target:
        return img_rgb
    scale = target / float(long_side)
    new_w = max(1, int(round(w * scale)))
    new_h = max(1, int(round(h * scale)))
    interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_CUBIC
    return cv2.resize(img_rgb, (new_w, new_h), interpolation=interp)

def center_crop_or_pad_to_square(img_rgb, size=1024, pad_color=(0,0,0)):
    h, w = img_rgb.shape[:2]
    if w >= size and h >= size:
        x1 = (w - size) // 2
        y1 = (h - size) // 2
        return img_rgb[y1:y1+size, x1:x1+size, :]
    canvas = np.full((size, size, 3), pad_color, dtype=np.uint8)
    offx = (size - w) // 2
    offy = (size - h) // 2
    canvas[offy:offy+h, offx:offx+w] = img_rgb
    return canvas

# ---------- cascade resolution ----------
def resolve_cascade(name: str) -> str | None:
    candidates = []
    cv2_dir = Path(cv2.__file__).resolve().parent
    candidates.append(cv2_dir / "data" / name)
    candidates.append(cv2_dir / "haarcascades" / name)
    hb_prefixes = [Path("/opt/homebrew/opt/opencv"), Path("/usr/local/opt/opencv")]
    for p in hb_prefixes:
        candidates.append(p / "share" / "opencv4" / "haarcascades" / name)
        candidates.append(p / "share" / "OpenCV"  / "haarcascades" / name)
    for up in [cv2_dir.parent, cv2_dir.parent.parent, cv2_dir.parent.parent.parent]:
        candidates.append(up / "share" / "opencv4" / "haarcascades" / name)
    for c in candidates:
        if c.is_file():
            return str(c)
    return None

def iou(a, b):
    ax1, ay1, ax2, ay2 = a[:4]; bx1, by1, bx2, by2 = b[:4]
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
    inter = iw * ih
    if inter == 0: return 0.0
    aa = (ax2-ax1) * (ay2-ay1); bb = (bx2-bx1) * (by2-by1)
    return inter / (aa + bb - inter)

def detect_faces_voted(gray, img_w, img_h):
    # Preproc
    eq = cv2.equalizeHist(gray)

    # Load cascades
    names = [
        ("frontal_default", "haarcascade_frontalface_default.xml"),
        ("frontal_alt2",    "haarcascade_frontalface_alt2.xml"),
        ("frontal_alt",     "haarcascade_frontalface_alt.xml"),
        ("profile",         "haarcascade_profileface.xml"),
    ]
    params = [(1.05, 3), (1.10, 5)]

    dets = []
    for label, fname in names:
        path = resolve_cascade(fname)
        if not path:
            dlog(f"[FACE] missing cascade: {fname}")
            continue
        cas = cv2.CascadeClassifier(path)
        if cas.empty():
            dlog(f"[FACE] failed to load cascade: {path}")
            continue
        for sf, nn in params:
            faces = cas.detectMultiScale(eq, scaleFactor=sf, minNeighbors=nn, minSize=(48,48))
            if len(faces): dlog(f"[FACE] {label} sf={sf} nn={nn} -> {len(faces)}")
            for (x,y,w,h) in faces:
                dets.append([x,y,x+w,y+h,label])

    if not dets:
        return None

    # Aggregate overlapping detections (voting)
    keep = []
    used = [False]*len(dets)
    for i,a in enumerate(dets):
        if used[i]: continue
        group = [i]
        for j,b in enumerate(dets):
            if i==j or used[j]: continue
            if iou(a,b) >= IOU_THRESH:
                group.append(j)
        for g in group: used[g]=True
        support = len(group)
        if support < SUPPORT_N:
            continue
        xs1 = [dets[g][0] for g in group]; ys1 = [dets[g][1] for g in group]
        xs2 = [dets[g][2] for g in group]; ys2 = [dets[g][3] for g in group]
        labels = [dets[g][4] for g in group]
        box = [int(np.mean(xs1)), int(np.mean(ys1)), int(np.mean(xs2)), int(np.mean(ys2))]
        keep.append((box, labels, support))

    if not keep:
        dlog("[FACE] all groups rejected by voting")
        return None

    # Size & edge sanity
    img_area = img_w * img_h
    filtered = []
    for (x1,y1,x2,y2), labels, support in keep:
        w = x2-x1; h = y2-y1; area = w*h
        frac = area / img_area
        cx = (x1+x2)/2.0 / img_w; cy = (y1+y2)/2.0 / img_h
        if not (MIN_FACE_FRAC <= frac <= MAX_FACE_FRAC):
            dlog(f"[FACE] drop size frac={frac:.3f}")
            continue
        if (cx < EDGE_GUARD) or (cx > 1-EDGE_GUARD) or (cy < EDGE_GUARD) or (cy > 1-EDGE_GUARD):
            dlog(f"[FACE] drop edge-guard cx={cx:.3f} cy={cy:.3f}")
            continue
        filtered.append((x1,y1,x2,y2,labels,support))

    if not filtered:
        dlog("[FACE] all groups rejected by sanity checks")
        return None

    # Eye confirmation for frontal labels
    eye_xml = resolve_cascade("haarcascade_eye.xml") or resolve_cascade("haarcascade_eye_tree_eyeglasses.xml")
    final = []
    for x1,y1,x2,y2,labels,support in filtered:
        if eye_xml and any(lbl.startswith("frontal") for lbl in labels):
            roi_w = max(1, x2-x1); roi_h = max(1, y2-y1)
            ex1 = x1 + int(0.10*roi_w); ex2 = x2 - int(0.10*roi_w)
            ey1 = y1 + int(0.15*roi_h); ey2 = y1 + int(0.60*roi_h)
            ex1,ex2 = max(0,ex1), max(ex1+1, ex2)
            ey1,ey2 = max(0,ey1), max(ey1+1, ey2)
            roi = gray[ey1:ey2, ex1:ex2]
            eyes = cv2.CascadeClassifier(eye_xml).detectMultiScale(roi, 1.10, 3, minSize=(12,12))
            if len(eyes) == 0:
                dlog("[FACE] drop: no eyes in frontal candidate")
                continue
        final.append((x1,y1,x2,y2,labels,support))

    if not final:
        dlog("[FACE] all candidates dropped after eye check")
        return None

    # pick largest remaining
    best = max(final, key=lambda b: (b[2]-b[0])*(b[3]-b[1]))
    return best  # (x1,y1,x2,y2,labels,support)

def main():
    if len(sys.argv) < 3:
        return 2
    inp = Path(sys.argv[1]); outp = Path(sys.argv[2])
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024

    img_bgr = cv2.imread(str(inp))
    if img_bgr is None:
        return 2
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    h, w = img_rgb.shape[:2]
    pad_color = edge_avg_color(img_rgb)

    gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY)
    best = detect_faces_voted(gray, w, h)

    if best is None:
        dlog("NO_FACE")
        scaled = resize_long_side_to(img_rgb, target=size)
        result = center_crop_or_pad_to_square(scaled, size=size, pad_color=pad_color)
    else:
        x1,y1,x2,y2,labels,support = best
        dlog(f"FACE_FOUND labels={labels} support={support} box=({x1},{y1},{x2},{y2}) size=({w}x{h})")
        fw, fh = (x2-x1), (y2-y1)
        side = int(max(fw, fh) * MARGIN_K)
        side = max(side, min(w, h)//2)
        side = min(side, int(max(w, h)*1.10))
        fcx = (x1 + x2) / 2.0; fcy = (y1 + y2) / 2.0
        half = side/2.0
        box = (int(fcx - half), int(fcy - half), int(fcx + half), int(fcy + half))
        result = paste_with_padding(img_rgb, box, side, pad_color)
        result = cv2.resize(result, (size, size), interpolation=cv2.INTER_LANCZOS4)

    Image.fromarray(result).save(outp, format="PNG")
    return 0

if __name__ == "__main__":
    sys.exit(main())
PYEOF
chmod +x "$FACEPY"

# -------- PROCESSOR --------
process_one() {
  local in="$1" out="$2"
  local size=1024

  if [[ "$FACE_AWARE" = "1" && -x "$PYTHON_BIN" ]]; then
    FACE_DEBUG="$DEBUG" "$PYTHON_BIN" - <<'PYCHK' >/dev/null 2>&1
import cv2
from PIL import Image
PYCHK
    if [[ $? -eq 0 ]]; then
      FACE_DEBUG="$DEBUG" "$PYTHON_BIN" "$FACEPY" "$in" "$out" "$size" || {
        echo "[WARN] face_crop.py failed on $(basename "$in"); falling back to center-crop." >&2
        /usr/bin/sips -s format png "$in" --out "${TMP_DIR}/step1-$$.png" >/dev/null
        local w h
        w=$(/usr/bin/sips -g pixelWidth  "${TMP_DIR}/step1-$$.png" | awk '/pixelWidth/ {print $2}')
        h=$(/usr/bin/sips -g pixelHeight "${TMP_DIR}/step1-$$.png" | awk '/pixelHeight/ {print $2}')
        if (( w <= h )); then
          /usr/bin/sips --resampleWidth  "$size" "${TMP_DIR}/step1-$$.png" >/dev/null
        else
          /usr/bin/sips --resampleHeight "$size" "${TMP_DIR}/step1-$$.png" >/dev/null
        fi
        /usr/bin/sips --cropToHeightWidth "$size" "$size" "${TMP_DIR}/step1-$$.png" --out "$out" >/dev/null
        rm -f "${TMP_DIR}/step1-$$.png"
      }
    else
      /usr/bin/sips -s format png "$in" --out "${TMP_DIR}/step1-$$.png" >/dev/null
      local w h
      w=$(/usr/bin/sips -g pixelWidth  "${TMP_DIR}/step1-$$.png" | awk '/pixelWidth/ {print $2}')
      h=$(/usr/bin/sips -g pixelHeight "${TMP_DIR}/step1-$$.png" | awk '/pixelHeight/ {print $2}')
      if (( w <= h )); then
        /usr/bin/sips --resampleWidth  "$size" "${TMP_DIR}/step1-$$.png" >/dev/null
      else
        /usr/bin/sips --resampleHeight "$size" "${TMP_DIR}/step1-$$.png" >/dev/null
      fi
      /usr/bin/sips --cropToHeightWidth "$size" "$size" "${TMP_DIR}/step1-$$.png" --out "$out" >/dev/null
      rm -f "${TMP_DIR}/step1-$$.png"
    fi
  else
    /usr/bin/sips -s format png "$in" --out "${TMP_DIR}/step1-$$.png" >/dev/null
    local w h
    w=$(/usr/bin/sips -g pixelWidth  "${TMP_DIR}/step1-$$.png" | awk '/pixelWidth/ {print $2}')
    h=$(/usr/bin/sips -g pixelHeight "${TMP_DIR}/step1-$$.png" | awk '/pixelHeight/ {print $2}')
    if (( w <= h )); then
      /usr/bin/sips --resampleWidth  "$size" "${TMP_DIR}/step1-$$.png" >/dev/null
    else
      /usr/bin/sips --resampleHeight "$size" "${TMP_DIR}/step1-$$.png" >/dev/null
    fi
    /usr/bin/sips --cropToHeightWidth "$size" "$size" "${TMP_DIR}/step1-$$.png" --out "$out" >/dev/null
    rm -f "${TMP_DIR}/step1-$$.png"
  fi

  # Strip metadata
  if [[ -n "$EXIFTOOL" ]]; then
    "$EXIFTOOL" -overwrite_original -all= "$out" >/dev/null || echo "[WARN] exiftool failed on $out" >&2
  else
    xattr -c "$out" >/dev/null 2>&1 || true
  fi
}

# -------- GATHER FILES, THEN PROCESS --------
typeset -a files
while IFS= read -r -d '' f; do
  [[ "$(basename "$f")" == .tmp* ]] && continue
  files+=("$f")
done < <(find "$PROC_DIR" -maxdepth 1 -type f -print0)

count=0
errors=0

for f in "${files[@]}"; do
  (( ++count ))
  newbase=$(printf "%02d_%s.png" "$count" "$LORA_NAME")
  outpath="${PROC_DIR}/${newbase}"

  log "Processing: $(basename "$f") -> $newbase"
  if process_one "$f" "$outpath"; then
    rm -f "$f"
  else
    echo "[ERROR] Failed to process: $f" >&2
    ((errors++)) || true
  fi
done

# -------- SUMMARY --------
if (( errors > 0 )); then
  osascript -e "display alert \"Done with errors\" message \"Processed $count files. $errors failed. Run with DEBUG=1 for details.\" buttons {\"OK\"} default button \"OK\""
else
  osascript -e 'display notification "Processing complete." with title "Prep LoRA Images (face-aware + no-face scale/crop/pad)"'
fi

open "$PROC_DIR"
