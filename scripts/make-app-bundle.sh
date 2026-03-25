#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="${1:-${BUILD_CONFIG:-release}}"

if [[ "$BUILD_CONFIG" != "release" && "$BUILD_CONFIG" != "debug" ]]; then
  echo "Invalid build config: $BUILD_CONFIG (expected: release|debug)" >&2
  exit 1
fi

BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIG"
APP_BIN="$BUILD_DIR/FricuApp"
APP_BUNDLE="$BUILD_DIR/fr-training.app"
APP_EXEC="$APP_BUNDLE/Contents/MacOS/FricuApp"
INFO_PLIST_SRC="$ROOT_DIR/Sources/FricuApp/Info.plist"
ICON_MASTER_PPM="$ROOT_DIR/Sources/FricuApp/Resources/AppIcon-master.ppm"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_ICNS="$BUILD_DIR/AppIcon.icns"
DIST_DIR="$ROOT_DIR/dist/$BUILD_CONFIG"
DIST_BIN="$DIST_DIR/fr-training"
DIST_BUNDLE="$DIST_DIR/fr-training.app"
DIST_ROOT_BIN="$ROOT_DIR/dist/fr-training"
DIST_ROOT_BUNDLE="$ROOT_DIR/dist/fr-training.app"
LEGACY_DIST_BIN="$DIST_DIR/FricuApp"
LEGACY_DIST_BUNDLE="$DIST_DIR/FricuApp.app"
LEGACY_DIST_ROOT_BIN="$ROOT_DIR/dist/FricuApp"
LEGACY_DIST_ROOT_BUNDLE="$ROOT_DIR/dist/FricuApp.app"
MOTIONBERT_RUNTIME_DIR_NAME="MotionBERTRuntime"
BIKE_KEYPOINT_MODEL_DIR_NAME="BikeKeypointModel"
BIKE_KEYPOINT_TRAINING_DIR_NAME="BikeKeypointTraining"

resolve_resource_bundle() {
  local candidate=""
  for candidate in \
    "$BUILD_DIR/FricuApp_FricuApp.bundle" \
    "$BUILD_DIR/Fricu_FricuApp.bundle"
  do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

runtime_supports_motionbert() {
  local python_exec="$1"
  "$python_exec" - <<'PY' >/dev/null 2>&1
import importlib.util

required = ("mmpose", "mmengine", "mmdet")
if not all(importlib.util.find_spec(name) is not None for name in required):
    raise SystemExit(1)

try:
    import mmcv  # noqa: F401
    import mmcv._ext  # noqa: F401
except Exception:
    raise SystemExit(1)

raise SystemExit(0)
PY
}

copy_tree_following_symlinks() {
  local source_dir="$1"
  local destination_dir="$2"
  rm -rf "$destination_dir"
  mkdir -p "$(dirname "$destination_dir")"

  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "$destination_dir"
    rsync -aL --delete \
      --exclude '__pycache__' \
      --exclude '*.pyc' \
      --exclude '*.pyo' \
      "$source_dir"/ "$destination_dir"/
  else
    cp -R "$source_dir" "$destination_dir"
  fi
}

resolve_motionbert_runtime_dir() {
  local -a candidates=()
  local python_exec=""
  local derived_root=""

  if [[ -n "${FRICU_MMPPOSE_RUNTIME_DIR:-}" ]]; then
    candidates+=("${FRICU_MMPPOSE_RUNTIME_DIR}")
  fi

  for env_key in FRICU_MMPPOSE_PYTHON FRICU_VIDEO_POSE_PYTHON; do
    python_exec="${!env_key:-}"
    if [[ -n "$python_exec" && -x "$python_exec" ]]; then
      derived_root="$(cd "$(dirname "$python_exec")/.." && pwd)"
      candidates+=("$derived_root")
    fi
  done

  if [[ -n "${HOME:-}" ]]; then
    candidates+=(
      "$ROOT_DIR/.runtime/${MOTIONBERT_RUNTIME_DIR_NAME}"
      "$ROOT_DIR/runtime/${MOTIONBERT_RUNTIME_DIR_NAME}"
      "$HOME/miniconda3/envs/mmpose-mac"
      "$HOME/miniforge3/envs/mmpose-mac"
      "$HOME/anaconda3/envs/mmpose-mac"
      "$HOME/micromamba/envs/mmpose-mac"
      "$HOME/mambaforge/envs/mmpose-mac"
      "$HOME/miniconda3"
      "$HOME/miniforge3"
      "$HOME/anaconda3"
    )
  fi

  local candidate=""
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    for python_exec in "$candidate/bin/python" "$candidate/bin/python3"; do
      if [[ -x "$python_exec" ]] && runtime_supports_motionbert "$python_exec"; then
        echo "$candidate"
        return 0
      fi
    done
  done

  return 1
}

package_motionbert_runtime_if_available() {
  local runtime_dir=""
  if ! runtime_dir="$(resolve_motionbert_runtime_dir)"; then
    echo "warning: MotionBERT runtime not bundled (set FRICU_MMPPOSE_RUNTIME_DIR or FRICU_MMPPOSE_PYTHON to a Python runtime with mmpose + mmengine)" >&2
    return 0
  fi

  local runtime_bundle_dir="$APP_BUNDLE/Contents/Resources/${MOTIONBERT_RUNTIME_DIR_NAME}"
  echo "Packaging MotionBERT runtime from: $runtime_dir" >&2
  copy_tree_following_symlinks "$runtime_dir" "$runtime_bundle_dir"

  local copied_cache=0
  local cache_candidate=""
  for cache_candidate in "${FRICU_MMPPOSE_CACHE_DIR:-}" "${HOME:-}/.cache/mim" "${HOME:-}/.cache/openmmlab" "${HOME:-}/.cache/torch"; do
    [[ -n "$cache_candidate" && -d "$cache_candidate" ]] || continue
    mkdir -p "$runtime_bundle_dir/cache"
    copy_tree_following_symlinks "$cache_candidate" "$runtime_bundle_dir/cache/$(basename "$cache_candidate")"
    copied_cache=1
  done

  if [[ "$copied_cache" == "1" ]]; then
    echo "Packaged MotionBERT model cache into: $runtime_bundle_dir/cache" >&2
  fi
}

checkpoint_mod_time() {
  local checkpoint_path="$1"
  if stat -f %m "$checkpoint_path" >/dev/null 2>&1; then
    stat -f %m "$checkpoint_path"
  else
    stat -c %Y "$checkpoint_path"
  fi
}

resolve_bike_keypoint_checkpoint() {
  local -a explicit_candidates=()
  local checkpoint_path=""

  if [[ -n "${FRICU_BIKE_KEYPOINT_CHECKPOINT:-}" ]]; then
    explicit_candidates+=("${FRICU_BIKE_KEYPOINT_CHECKPOINT}")
  fi

  if [[ -n "${FRICU_BIKE_KEYPOINT_MODEL_DIR:-}" ]]; then
    explicit_candidates+=("${FRICU_BIKE_KEYPOINT_MODEL_DIR}/best.pt")
  fi

  if [[ "${#explicit_candidates[@]}" -gt 0 ]]; then
    for checkpoint_path in "${explicit_candidates[@]}"; do
      [[ -n "$checkpoint_path" && -f "$checkpoint_path" ]] || continue
      echo "$checkpoint_path"
      return 0
    done
  fi

  local latest_checkpoint=""
  local latest_mtime=0
  if [[ -d "$ROOT_DIR/.runtime/BikeKeypointSelfTrain" ]]; then
    while IFS= read -r -d '' checkpoint_path; do
      [[ -f "$checkpoint_path" ]] || continue
      local checkpoint_mtime
      checkpoint_mtime="$(checkpoint_mod_time "$checkpoint_path")"
      if [[ -z "$latest_checkpoint" || "$checkpoint_mtime" -gt "$latest_mtime" ]]; then
        latest_checkpoint="$checkpoint_path"
        latest_mtime="$checkpoint_mtime"
      fi
    done < <(find "$ROOT_DIR/.runtime/BikeKeypointSelfTrain" -type f -name 'best.pt' -print0)
  fi

  [[ -n "$latest_checkpoint" ]] || return 1
  echo "$latest_checkpoint"
}

package_bike_keypoint_model_if_available() {
  local checkpoint_path=""
  if ! checkpoint_path="$(resolve_bike_keypoint_checkpoint)"; then
    echo "warning: Bike keypoint checkpoint not bundled (set FRICU_BIKE_KEYPOINT_CHECKPOINT or train a checkpoint under .runtime/BikeKeypointSelfTrain)" >&2
    return 0
  fi

  local model_bundle_dir="$APP_BUNDLE/Contents/Resources/${BIKE_KEYPOINT_MODEL_DIR_NAME}"
  mkdir -p "$model_bundle_dir"
  cp "$checkpoint_path" "$model_bundle_dir/best.pt"

  local metadata_path="${checkpoint_path%.pt}.json"
  if [[ -f "$metadata_path" ]]; then
    cp "$metadata_path" "$model_bundle_dir/best.json"
  fi

  echo "Packaged bike keypoint checkpoint from: $checkpoint_path" >&2
}

package_bike_keypoint_training_script() {
  local script_path="$ROOT_DIR/scripts/bike_keypoint_selftrain.py"
  if [[ ! -f "$script_path" ]]; then
    echo "warning: Bike keypoint training script not found at $script_path" >&2
    return 0
  fi

  local training_bundle_dir="$APP_BUNDLE/Contents/Resources/${BIKE_KEYPOINT_TRAINING_DIR_NAME}"
  mkdir -p "$training_bundle_dir"
  cp "$script_path" "$training_bundle_dir/bike_keypoint_selftrain.py"
  echo "Packaged bike keypoint training script from: $script_path" >&2
}

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing app binary: $APP_BIN" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST_SRC" ]]; then
  echo "Missing Info.plist template: $INFO_PLIST_SRC" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$APP_BIN" "$APP_EXEC"
chmod +x "$APP_EXEC"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

RESOURCE_BUNDLE=""
if RESOURCE_BUNDLE="$(resolve_resource_bundle)"; then
  RESOURCE_BUNDLE_NAME="$(basename "$RESOURCE_BUNDLE")"
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/$RESOURCE_BUNDLE_NAME"
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE_NAME"
fi

package_motionbert_runtime_if_available
package_bike_keypoint_model_if_available
package_bike_keypoint_training_script

mkdir -p "$DIST_DIR"
rm -rf "$DIST_BUNDLE"
cp "$APP_BIN" "$DIST_BIN"
chmod +x "$DIST_BIN"
cp -R "$APP_BUNDLE" "$DIST_BUNDLE"
rm -f "$LEGACY_DIST_BIN"
ln -sfn "$(basename "$DIST_BIN")" "$LEGACY_DIST_BIN"
rm -rf "$LEGACY_DIST_BUNDLE"
ln -sfn "$(basename "$DIST_BUNDLE")" "$LEGACY_DIST_BUNDLE"

cp "$DIST_BIN" "$DIST_ROOT_BIN"
chmod +x "$DIST_ROOT_BIN"
rm -rf "$DIST_ROOT_BUNDLE"
cp -R "$DIST_BUNDLE" "$DIST_ROOT_BUNDLE"
rm -f "$LEGACY_DIST_ROOT_BIN"
ln -sfn "$(basename "$DIST_ROOT_BIN")" "$LEGACY_DIST_ROOT_BIN"
rm -rf "$LEGACY_DIST_ROOT_BUNDLE"
ln -sfn "$(basename "$DIST_ROOT_BUNDLE")" "$LEGACY_DIST_ROOT_BUNDLE"

if [[ "$(uname -s)" == "Darwin" ]]; then
  "$ROOT_DIR/scripts/generate-app-icon.py" >/dev/null
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  if [[ -f "$ICON_MASTER_PPM" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    for size in 16 32 64 128 256 512; do
      sips -s format png -z "$size" "$size" "$ICON_MASTER_PPM" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
      retina=$((size * 2))
      sips -s format png -z "$retina" "$retina" "$ICON_MASTER_PPM" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
    cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    cp "$ICON_ICNS" "$DIST_BUNDLE/Contents/Resources/AppIcon.icns"
    cp "$ICON_ICNS" "$DIST_ROOT_BUNDLE/Contents/Resources/AppIcon.icns"
  else
    echo "warning: icon generation tools missing (need sips + iconutil), skipping app icon generation" >&2
  fi
fi

echo "$DIST_BUNDLE"
