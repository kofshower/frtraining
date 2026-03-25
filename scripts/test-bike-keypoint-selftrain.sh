#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/bike_keypoint_selftrain.py"

resolve_python() {
  local candidates=()
  if [[ -n "${FRICU_BIKE_KEYPOINT_PYTHON:-}" ]]; then
    candidates+=("${FRICU_BIKE_KEYPOINT_PYTHON}")
  fi
  if [[ -n "${FRICU_MMPPOSE_PYTHON:-}" ]]; then
    candidates+=("${FRICU_MMPPOSE_PYTHON}")
  fi
  candidates+=(
    "$HOME/miniconda3/envs/mmpose-mac/bin/python"
    "$HOME/miniforge3/envs/mmpose-mac/bin/python"
    "$(command -v python3 || true)"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

PYTHON_BIN="$(resolve_python)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[bike-selftrain] using python: $PYTHON_BIN"
"$PYTHON_BIN" "$SCRIPT_PATH" synthetic-dataset \
  --output-dir "$TMP_DIR/synth" \
  --count 24 \
  --image-size 192 \
  --seed 17 >/dev/null

"$PYTHON_BIN" "$SCRIPT_PATH" train \
  --dataset "$TMP_DIR/synth/dataset.json" \
  --output-dir "$TMP_DIR/run" \
  --epochs 4 \
  --batch-size 6 \
  --image-size 192 \
  --device cpu \
  --workers 0 >/dev/null

"$PYTHON_BIN" "$SCRIPT_PATH" evaluate \
  --dataset "$TMP_DIR/synth/dataset.json" \
  --checkpoint "$TMP_DIR/run/best.pt" \
  --device cpu >"$TMP_DIR/eval.json"

"$PYTHON_BIN" - <<'PY' "$TMP_DIR/eval.json"
import json
import math
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = ("mean_pixel_error", "mean_score", "nme")
for key in required:
    if key not in payload:
        raise SystemExit(f"missing metric: {key}")
    value = float(payload[key])
    if not math.isfinite(value):
        raise SystemExit(f"non-finite metric: {key}={value}")
if payload["mean_pixel_error"] > 45:
    raise SystemExit(f"synthetic smoke test diverged: mean_pixel_error={payload['mean_pixel_error']}")
print("bike keypoint self-train smoke test passed")
PY
