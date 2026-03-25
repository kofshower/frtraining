#!/usr/bin/env python3
"""Self-training pipeline for road-bike BB / crank / pedal keypoints.

This script intentionally favors a practical self-supervised workflow over
fully unsupervised keypoint discovery. The keypoints we care about are
semantic and fixed:

1. ``bb_center``: bottom bracket center
2. ``crank_end``: pedal axle / crank arm endpoint
3. ``pedal_center``: pedal platform proxy under the forefoot

For real riding videos, pseudo labels are derived from the existing human pose
pipeline and robust circle fitting. A compact heatmap network can then be
trained on those pseudo labels with an additional flip-consistency loss.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


KEYPOINT_NAMES = ("bb_center", "crank_end", "pedal_center")
PEDAL_CENTER_RATIO = 0.62
DATASET_SCHEMA = "fr-training-bike-keypoints-v1"
DEFAULT_INPUT_SIZE = 256
DEFAULT_HEATMAP_STRIDE = 4
PROGRESS_PREFIX = "FRICU_PROGRESS"


def emit_progress(stage: str, **fields: Any) -> None:
    components = [PROGRESS_PREFIX, stage]
    for key, value in fields.items():
        components.append(f"{key}={value}")
    print("|".join(components), file=sys.stderr, flush=True)


def _load_cv2_numpy():
    import cv2  # type: ignore
    import numpy as np  # type: ignore

    return cv2, np


def _load_torch():
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    from torch.utils.data import DataLoader, Dataset

    return torch, nn, F, DataLoader, Dataset


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def mediapipe_pose_script_path() -> Path:
    script_dir = Path(__file__).resolve().parent
    candidates = [
        repo_root() / "Sources" / "FricuApp" / "Resources" / "PoseModels" / "video_pose_mediapipe.py",
        script_dir.parent / "FricuApp_FricuApp.bundle" / "video_pose_mediapipe.py",
        script_dir.parent / "Fricu_FricuApp.bundle" / "video_pose_mediapipe.py",
        script_dir.parent / "PoseModels" / "video_pose_mediapipe.py",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def resolve_pose_python(explicit: Optional[str] = None) -> str:
    candidates: List[Optional[str]] = [
        explicit,
        os.environ.get("FRICU_BIKE_KEYPOINT_PYTHON"),
        os.environ.get("FRICU_MEDIAPIPE_PYTHON"),
        os.environ.get("FRICU_MMPPOSE_PYTHON"),
        str(Path.home() / "miniconda3" / "envs" / "mmpose-mac" / "bin" / "python"),
        str(Path.home() / "miniforge3" / "envs" / "mmpose-mac" / "bin" / "python"),
        str(Path.home() / "anaconda3" / "envs" / "mmpose-mac" / "bin" / "python"),
        sys.executable,
        shutil.which("python3"),
    ]
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.exists():
            return str(path)
    raise RuntimeError("No usable Python runtime found for bike keypoint self-training.")


def resolve_training_device(explicit: Optional[str] = None) -> str:
    if explicit:
        return explicit
    torch, _, _, _, _ = _load_torch()
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def point_distance(a: Dict[str, float], b: Dict[str, float]) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def blend_point(a: Dict[str, float], b: Dict[str, float], ratio: float) -> Dict[str, float]:
    confidence = min(float(a.get("confidence", 0.0)), float(b.get("confidence", 0.0)))
    return {
        "x": float(a["x"] + (b["x"] - a["x"]) * ratio),
        "y": float(a["y"] + (b["y"] - a["y"]) * ratio),
        "confidence": confidence,
    }


def normalize_point(point: Dict[str, float], width: int, height: int) -> Dict[str, float]:
    return {
        "x": float(point["x"]) / float(max(1, width)),
        "y": float(point["y"]) / float(max(1, height)),
        "confidence": float(point.get("confidence", 0.0)),
    }


def denormalize_point(point: Dict[str, float], width: int, height: int) -> Dict[str, float]:
    return {
        "x": float(point["x"]) * float(width),
        "y": float(point["y"]) * float(height),
        "confidence": float(point.get("confidence", 0.0)),
    }


def approximate_toe(knee: Optional[Dict[str, float]], ankle: Dict[str, float]) -> Dict[str, float]:
    if knee is None:
        return dict(ankle)
    vx = ankle["x"] - knee["x"]
    vy = ankle["y"] - knee["y"]
    confidence = min(float(ankle.get("confidence", 0.0)), float(knee.get("confidence", 0.0))) * 0.7
    return {
        "x": ankle["x"] + vx * 0.35,
        "y": ankle["y"] + vy * 0.35,
        "confidence": confidence,
    }


def solve_circle(points: Sequence[Dict[str, float]]) -> Optional[Tuple[float, float, float]]:
    _, np = _load_cv2_numpy()
    if len(points) < 3:
        return None
    coords = np.array([[float(p["x"]), float(p["y"])] for p in points], dtype=np.float64)
    x = coords[:, 0]
    y = coords[:, 1]
    a = np.column_stack((2.0 * x, 2.0 * y, np.ones(len(coords), dtype=np.float64)))
    b = x * x + y * y
    solution, _, rank, _ = np.linalg.lstsq(a, b, rcond=None)
    if rank < 3:
        return None
    cx = float(solution[0])
    cy = float(solution[1])
    radius_sq = float(solution[2] + cx * cx + cy * cy)
    if not math.isfinite(radius_sq) or radius_sq <= 0:
        return None
    radius = math.sqrt(radius_sq)
    if not math.isfinite(cx) or not math.isfinite(cy) or not math.isfinite(radius):
        return None
    return cx, cy, radius


def fit_circle_robust(points: Sequence[Dict[str, float]]) -> Optional[Tuple[Dict[str, float], float, List[int], float]]:
    if len(points) < 6:
        return None
    initial = solve_circle(points)
    if initial is None:
        return None
    cx, cy, radius = initial
    residuals = [abs(math.hypot(p["x"] - cx, p["y"] - cy) - radius) for p in points]
    sorted_residuals = sorted(residuals)
    median_residual = sorted_residuals[len(sorted_residuals) // 2]
    threshold = max(4.0, radius * 0.18, median_residual * 2.5)
    inlier_indices = [index for index, value in enumerate(residuals) if value <= threshold]
    if len(inlier_indices) < 6:
        return None
    inlier_points = [points[index] for index in inlier_indices]
    refined = solve_circle(inlier_points)
    if refined is None:
        return None
    cx, cy, radius = refined
    rms = math.sqrt(
        sum((math.hypot(p["x"] - cx, p["y"] - cy) - radius) ** 2 for p in inlier_points) / float(len(inlier_points))
    )
    confidence_values = [float(points[index].get("confidence", 0.0)) for index in inlier_indices]
    confidence = sum(confidence_values) / float(max(1, len(confidence_values)))
    return ({"x": cx, "y": cy, "confidence": confidence}, radius, inlier_indices, rms)


def project_onto_circle(center: Dict[str, float], radius: float, point: Dict[str, float]) -> Optional[Dict[str, float]]:
    dx = point["x"] - center["x"]
    dy = point["y"] - center["y"]
    length = math.hypot(dx, dy)
    if length < 1e-6:
        return None
    scale = radius / length
    return {
        "x": center["x"] + dx * scale,
        "y": center["y"] + dy * scale,
        "confidence": float(point.get("confidence", 0.0)),
    }


def average(values: Iterable[float]) -> float:
    values = list(values)
    if not values:
        return 0.0
    return sum(values) / float(len(values))


def keypoint_visibility(point: Optional[Dict[str, float]]) -> float:
    if point is None:
        return 0.0
    return float(point.get("confidence", 0.0))


def sample_side_confidence(sample: Dict[str, Any], side: str) -> float:
    joints = sample.get("joints", {})
    keys = [f"{side}_hip", f"{side}_knee", f"{side}_ankle", f"{side}_foot_index"]
    return average(keypoint_visibility(joints.get(key)) for key in keys)


def dominant_side(samples: Sequence[Dict[str, Any]]) -> str:
    left_score = average(sample_side_confidence(sample, "left") for sample in samples)
    right_score = average(sample_side_confidence(sample, "right") for sample in samples)
    return "left" if left_score >= right_score else "right"


def run_pose_pseudo_backend(video_path: Path, max_samples: int, python_executable: str) -> Dict[str, Any]:
    script_path = mediapipe_pose_script_path()
    if not script_path.exists():
        raise RuntimeError(f"MediaPipe pose script not found: {script_path}")
    result = subprocess.run(
        [python_executable, str(script_path), "--video", str(video_path), "--max-samples", str(max_samples)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        error_text = result.stderr.strip() or result.stdout.strip() or "unknown pose backend error"
        raise RuntimeError(error_text)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Pose backend returned invalid JSON.") from exc


def frame_indices_from_pose_samples(samples: Sequence[Dict[str, Any]], fps: float) -> List[int]:
    indices: List[int] = []
    for sample in samples:
        time_seconds = float(sample.get("time_seconds", 0.0))
        indices.append(max(0, int(round(time_seconds * fps))))
    return indices


def extract_pseudo_labels_for_video(
    video_path: Path,
    output_dir: Path,
    max_samples: int,
    python_executable: str,
    min_quality: float,
) -> Dict[str, Any]:
    cv2, _ = _load_cv2_numpy()
    pose_payload = run_pose_pseudo_backend(video_path, max_samples=max_samples, python_executable=python_executable)
    pose_samples = pose_payload.get("samples", [])
    if not pose_samples:
        raise RuntimeError(f"No pose samples returned for {video_path.name}.")

    side = dominant_side(pose_samples)
    pedal_candidates: List[Dict[str, float]] = []
    enriched_samples: List[Dict[str, Any]] = []

    for sample in pose_samples:
        joints = sample.get("joints", {})
        ankle = joints.get(f"{side}_ankle")
        knee = joints.get(f"{side}_knee")
        foot = joints.get(f"{side}_foot_index")
        if ankle is None:
            continue
        if foot is None:
            foot = approximate_toe(knee, ankle)
        pedal_center = blend_point(ankle, foot, PEDAL_CENTER_RATIO)
        pedal_candidates.append(
            {
                "x": float(pedal_center["x"]),
                "y": float(pedal_center["y"]),
                "confidence": average(
                    [
                        float(ankle.get("confidence", 0.0)),
                        float(foot.get("confidence", 0.0)),
                        float(knee.get("confidence", 0.0)) if knee else 0.0,
                    ]
                ),
            }
        )
        enriched_samples.append(
            {
                "time_seconds": float(sample.get("time_seconds", 0.0)),
                "pedal_center_norm": pedal_center,
                "raw_sample": sample,
            }
        )

    fit = fit_circle_robust(pedal_candidates)
    if fit is None:
        raise RuntimeError(f"Unable to fit a reliable crank circle for {video_path.name}.")
    bb_center_norm, radius_norm, inlier_indices, rms = fit
    inlier_times = {round(float(enriched_samples[index]["time_seconds"]), 6) for index in inlier_indices if index < len(enriched_samples)}

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Unable to open video: {video_path}")
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 0:
        fps = 30.0

    images_dir = output_dir / "images"
    ensure_dir(images_dir)
    records: List[Dict[str, Any]] = []

    for frame_id, sample in enumerate(enriched_samples):
        rounded_time = round(float(sample["time_seconds"]), 6)
        if rounded_time not in inlier_times:
            continue
        pedal_center_norm = sample["pedal_center_norm"]
        crank_end_norm = project_onto_circle(bb_center_norm, radius_norm, pedal_center_norm)
        if crank_end_norm is None:
            continue

        frame_index = max(0, int(round(float(sample["time_seconds"]) * fps)))
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok or frame is None:
            continue
        height, width = frame.shape[:2]

        bb_center_px = denormalize_point(bb_center_norm, width, height)
        pedal_center_px = denormalize_point(pedal_center_norm, width, height)
        crank_end_px = denormalize_point(crank_end_norm, width, height)
        residual_px = abs(point_distance(pedal_center_px, bb_center_px) - point_distance(crank_end_px, bb_center_px))

        quality = max(
            0.0,
            min(
                1.0,
                average(
                    [
                        float(bb_center_norm.get("confidence", 0.0)),
                        float(pedal_center_norm.get("confidence", 0.0)),
                        float(crank_end_norm.get("confidence", 0.0)),
                        max(0.0, 1.0 - residual_px / max(8.0, radius_norm * height * 0.35)),
                    ]
                ),
            ),
        )
        if quality < min_quality:
            continue

        file_name = f"{video_path.stem}-{frame_id:04d}.jpg"
        image_path = images_dir / file_name
        cv2.imwrite(str(image_path), frame)

        records.append(
            {
                "id": f"{video_path.stem}-{frame_id:04d}",
                "image_path": str(image_path),
                "video_path": str(video_path),
                "time_seconds": float(sample["time_seconds"]),
                "width": int(width),
                "height": int(height),
                "side": side,
                "quality": quality,
                "source": "pseudo",
                "keypoints": {
                    "bb_center": bb_center_norm,
                    "crank_end": crank_end_norm,
                    "pedal_center": pedal_center_norm,
                },
            }
        )

    cap.release()
    if not records:
        raise RuntimeError(f"No usable pseudo-label frames exported for {video_path.name}.")

    return {
        "video_path": str(video_path),
        "record_count": len(records),
        "dominant_side": side,
        "bb_center": bb_center_norm,
        "radius": radius_norm,
        "fit_rms": rms,
        "records": records,
        "warnings": pose_payload.get("warnings", []),
    }


def collect_video_paths(paths: Sequence[str]) -> List[Path]:
    collected: List[Path] = []
    for raw_path in paths:
        path = Path(raw_path).expanduser()
        if path.is_dir():
            for suffix in ("*.mp4", "*.mov", "*.m4v", "*.avi"):
                collected.extend(sorted(path.glob(suffix)))
        elif path.is_file():
            collected.append(path)
    unique: List[Path] = []
    seen = set()
    for path in collected:
        resolved = str(path.resolve())
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(path)
    return unique


def build_dataset_payload(records: Sequence[Dict[str, Any]], source_videos: Sequence[Path]) -> Dict[str, Any]:
    return {
        "schema": DATASET_SCHEMA,
        "keypoint_names": list(KEYPOINT_NAMES),
        "pedal_center_ratio": PEDAL_CENTER_RATIO,
        "source_videos": [str(path) for path in source_videos],
        "record_count": len(records),
        "records": list(records),
    }


@dataclass
class LetterboxTransform:
    scale: float
    pad_x: int
    pad_y: int
    output_size: int
    original_width: int
    original_height: int

    def forward_point(self, point_xy: Tuple[float, float]) -> Tuple[float, float]:
        x, y = point_xy
        return x * self.scale + self.pad_x, y * self.scale + self.pad_y

    def inverse_point(self, point_xy: Tuple[float, float]) -> Tuple[float, float]:
        x, y = point_xy
        return (x - self.pad_x) / max(self.scale, 1e-8), (y - self.pad_y) / max(self.scale, 1e-8)


def letterbox_image(image, output_size: int) -> Tuple[Any, LetterboxTransform]:
    cv2, np = _load_cv2_numpy()
    height, width = image.shape[:2]
    scale = min(float(output_size) / float(width), float(output_size) / float(height))
    resized_width = max(1, int(round(width * scale)))
    resized_height = max(1, int(round(height * scale)))
    resized = cv2.resize(image, (resized_width, resized_height), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((output_size, output_size, 3), 114, dtype=np.uint8)
    pad_x = (output_size - resized_width) // 2
    pad_y = (output_size - resized_height) // 2
    canvas[pad_y : pad_y + resized_height, pad_x : pad_x + resized_width] = resized
    transform = LetterboxTransform(
        scale=scale,
        pad_x=pad_x,
        pad_y=pad_y,
        output_size=output_size,
        original_width=width,
        original_height=height,
    )
    return canvas, transform


def gaussian_heatmap(height: int, width: int, center_xy: Tuple[float, float], sigma: float):
    _, np = _load_cv2_numpy()
    grid_x, grid_y = np.meshgrid(np.arange(width, dtype=np.float32), np.arange(height, dtype=np.float32))
    cx, cy = center_xy
    return np.exp(-((grid_x - cx) ** 2 + (grid_y - cy) ** 2) / (2.0 * sigma * sigma))


def make_heatmaps(
    keypoints_xy: Sequence[Tuple[float, float]],
    heatmap_size: int,
    sigma: float,
):
    _, np = _load_cv2_numpy()
    heatmaps = np.zeros((len(keypoints_xy), heatmap_size, heatmap_size), dtype=np.float32)
    for index, point_xy in enumerate(keypoints_xy):
        heatmaps[index] = gaussian_heatmap(heatmap_size, heatmap_size, point_xy, sigma)
    return heatmaps


def train_val_split(records: Sequence[Dict[str, Any]], val_ratio: float, seed: int) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    items = list(records)
    rng = random.Random(seed)
    rng.shuffle(items)
    if not items:
        return [], []
    val_count = max(1, int(round(len(items) * val_ratio))) if len(items) >= 4 else max(0, len(items) // 4)
    val_count = min(val_count, max(1, len(items) - 1)) if len(items) > 1 else 0
    val_items = items[:val_count]
    train_items = items[val_count:] if val_count > 0 else items
    return train_items, val_items


def checkpoint_metadata_path(checkpoint_path: Path) -> Path:
    return checkpoint_path.with_suffix(".json")


def load_dataset_records(dataset_path: Path) -> List[Dict[str, Any]]:
    payload = read_json(dataset_path)
    if payload.get("schema") != DATASET_SCHEMA:
        raise RuntimeError(f"Unsupported dataset schema: {payload.get('schema')}")
    records = payload.get("records", [])
    if not isinstance(records, list):
        raise RuntimeError("Dataset records must be a list.")
    return records


class BikeKeypointDatasetAdapter:
    def __init__(
        self,
        records: Sequence[Dict[str, Any]],
        input_size: int,
        heatmap_stride: int,
        augment: bool,
    ) -> None:
        torch, _, _, _, Dataset = _load_torch()
        cv2, np = _load_cv2_numpy()

        class _Dataset(Dataset):
            def __init__(self, parent: "BikeKeypointDatasetAdapter") -> None:
                self.parent = parent

            def __len__(self) -> int:
                return len(self.parent.records)

            def __getitem__(self, index: int):
                record = self.parent.records[index]
                image = cv2.imread(record["image_path"], cv2.IMREAD_COLOR)
                if image is None:
                    raise RuntimeError(f"Unable to read image: {record['image_path']}")
                image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                image, transform = letterbox_image(image, self.parent.input_size)

                keypoints_xy: List[Tuple[float, float]] = []
                for name in KEYPOINT_NAMES:
                    point = denormalize_point(record["keypoints"][name], record["width"], record["height"])
                    px, py = transform.forward_point((point["x"], point["y"]))
                    keypoints_xy.append((px, py))

                if self.parent.augment:
                    if random.random() < 0.5:
                        image = image[:, ::-1].copy()
                        keypoints_xy = [(self.parent.input_size - 1 - x, y) for x, y in keypoints_xy]
                    if random.random() < 0.8:
                        alpha = 1.0 + random.uniform(-0.12, 0.12)
                        beta = random.uniform(-14.0, 14.0)
                        image = np.clip(image.astype(np.float32) * alpha + beta, 0, 255).astype(np.uint8)

                heatmap_size = self.parent.input_size // self.parent.heatmap_stride
                scaled_points = [(x / self.parent.heatmap_stride, y / self.parent.heatmap_stride) for x, y in keypoints_xy]
                heatmaps = make_heatmaps(
                    scaled_points,
                    heatmap_size=heatmap_size,
                    sigma=max(1.4, heatmap_size / 32.0),
                )

                image_tensor = torch.from_numpy(image.transpose(2, 0, 1)).float() / 255.0
                heatmap_tensor = torch.from_numpy(heatmaps).float()
                keypoint_tensor = torch.tensor(keypoints_xy, dtype=torch.float32)
                return {
                    "image": image_tensor,
                    "heatmaps": heatmap_tensor,
                    "keypoints": keypoint_tensor,
                    "record_id": record["id"],
                }

        self.records = list(records)
        self.input_size = int(input_size)
        self.heatmap_stride = int(heatmap_stride)
        self.augment = bool(augment)
        self.dataset = _Dataset(self)


def build_bike_keypoint_model(num_keypoints: int):
    _, nn, _, _, _ = _load_torch()

    class ConvBlock(nn.Module):
        def __init__(self, in_channels: int, out_channels: int, stride: int = 1) -> None:
            super().__init__()
            self.layers = nn.Sequential(
                nn.Conv2d(in_channels, out_channels, kernel_size=3, stride=stride, padding=1, bias=False),
                nn.BatchNorm2d(out_channels),
                nn.ReLU(inplace=True),
                nn.Conv2d(out_channels, out_channels, kernel_size=3, stride=1, padding=1, bias=False),
                nn.BatchNorm2d(out_channels),
                nn.ReLU(inplace=True),
            )

        def forward(self, x):
            return self.layers(x)

    class BikeKeypointNet(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.stem = ConvBlock(3, 32, stride=2)
            self.down1 = ConvBlock(32, 64, stride=2)
            self.context = nn.Sequential(
                ConvBlock(64, 96, stride=1),
                ConvBlock(96, 96, stride=1),
            )
            self.head = nn.Sequential(
                nn.Conv2d(96, 64, kernel_size=3, padding=1, bias=False),
                nn.BatchNorm2d(64),
                nn.ReLU(inplace=True),
                nn.Conv2d(64, num_keypoints, kernel_size=1),
            )

        def forward(self, x):
            x = self.stem(x)
            x = self.down1(x)
            x = self.context(x)
            return self.head(x)

    return BikeKeypointNet()


def decode_heatmaps(heatmaps, heatmap_stride: int) -> Tuple[List[Tuple[float, float]], List[float]]:
    _, np = _load_cv2_numpy()
    channels, height, width = heatmaps.shape
    points: List[Tuple[float, float]] = []
    scores: List[float] = []
    for index in range(channels):
        heatmap = heatmaps[index]
        flat_index = int(np.argmax(heatmap))
        y, x = divmod(flat_index, width)
        score = float(heatmap[y, x])
        points.append(((x + 0.5) * heatmap_stride, (y + 0.5) * heatmap_stride))
        scores.append(score)
    return points, scores


def evaluate_model_records(
    model,
    records: Sequence[Dict[str, Any]],
    input_size: int,
    heatmap_stride: int,
    device: str,
) -> Dict[str, float]:
    torch, _, _, DataLoader, _ = _load_torch()
    if not records:
        return {"mean_pixel_error": 0.0, "mean_score": 0.0, "nme": 0.0}
    adapter = BikeKeypointDatasetAdapter(records, input_size=input_size, heatmap_stride=heatmap_stride, augment=False)
    loader = DataLoader(adapter.dataset, batch_size=8, shuffle=False, num_workers=0)
    model.eval()
    pixel_errors: List[float] = []
    scores: List[float] = []
    with torch.no_grad():
        for batch in loader:
            images = batch["image"].to(device)
            predictions = torch.sigmoid(model(images)).cpu().numpy()
            truth = batch["keypoints"].cpu().numpy()
            for pred_heatmaps, true_points in zip(predictions, truth):
                decoded_points, decoded_scores = decode_heatmaps(pred_heatmaps, heatmap_stride=heatmap_stride)
                for (pred_x, pred_y), (true_x, true_y), score in zip(decoded_points, true_points, decoded_scores):
                    pixel_errors.append(math.hypot(float(pred_x - true_x), float(pred_y - true_y)))
                    scores.append(float(score))
    image_diagonal = math.sqrt(input_size * input_size + input_size * input_size)
    mean_error = sum(pixel_errors) / float(max(1, len(pixel_errors)))
    return {
        "mean_pixel_error": mean_error,
        "mean_score": sum(scores) / float(max(1, len(scores))),
        "nme": mean_error / max(1.0, image_diagonal),
    }


def train_model(
    dataset_path: Path,
    output_dir: Path,
    epochs: int,
    batch_size: int,
    input_size: int,
    heatmap_stride: int,
    learning_rate: float,
    weight_decay: float,
    val_ratio: float,
    consistency_weight: float,
    seed: int,
    device: str,
    workers: int,
) -> Dict[str, Any]:
    torch, _, F, DataLoader, _ = _load_torch()
    records = load_dataset_records(dataset_path)
    train_records, val_records = train_val_split(records, val_ratio=val_ratio, seed=seed)
    if not train_records:
        raise RuntimeError("Training dataset is empty.")

    random.seed(seed)
    torch.manual_seed(seed)

    train_adapter = BikeKeypointDatasetAdapter(
        train_records,
        input_size=input_size,
        heatmap_stride=heatmap_stride,
        augment=True,
    )
    val_adapter = BikeKeypointDatasetAdapter(
        val_records,
        input_size=input_size,
        heatmap_stride=heatmap_stride,
        augment=False,
    )
    train_loader = DataLoader(
        train_adapter.dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=workers,
    )

    model = build_bike_keypoint_model(num_keypoints=len(KEYPOINT_NAMES)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=learning_rate, weight_decay=weight_decay)

    ensure_dir(output_dir)
    checkpoint_path = output_dir / "best.pt"
    metadata_path = checkpoint_metadata_path(checkpoint_path)

    emit_progress(
        "train_prepare",
        train_records=len(train_records),
        val_records=len(val_records),
        epochs=epochs,
        device=device,
    )

    best_val_error = float("inf")
    history: List[Dict[str, float]] = []
    for epoch_index in range(epochs):
        model.train()
        epoch_loss = 0.0
        epoch_steps = 0
        for batch in train_loader:
            images = batch["image"].to(device)
            target_heatmaps = batch["heatmaps"].to(device)
            predictions = torch.sigmoid(model(images))
            supervised_loss = F.mse_loss(predictions, target_heatmaps)
            flipped_images = torch.flip(images, dims=[3])
            flipped_predictions = torch.sigmoid(model(flipped_images))
            consistency_loss = F.mse_loss(predictions, torch.flip(flipped_predictions, dims=[3]))
            loss = supervised_loss + consistency_weight * consistency_loss

            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()

            epoch_loss += float(loss.item())
            epoch_steps += 1

        metrics = evaluate_model_records(
            model,
            val_records if val_records else train_records,
            input_size=input_size,
            heatmap_stride=heatmap_stride,
            device=device,
        )
        mean_loss = epoch_loss / float(max(1, epoch_steps))
        row = {
            "epoch": float(epoch_index + 1),
            "train_loss": mean_loss,
            "val_mean_pixel_error": metrics["mean_pixel_error"],
            "val_mean_score": metrics["mean_score"],
            "val_nme": metrics["nme"],
        }
        history.append(row)
        if metrics["mean_pixel_error"] < best_val_error:
            best_val_error = metrics["mean_pixel_error"]
            torch.save(
                {
                    "model_state": model.state_dict(),
                    "input_size": input_size,
                    "heatmap_stride": heatmap_stride,
                    "keypoint_names": list(KEYPOINT_NAMES),
                },
                checkpoint_path,
            )
            write_json(
                metadata_path,
                {
                    "schema": DATASET_SCHEMA,
                    "keypoint_names": list(KEYPOINT_NAMES),
                    "input_size": input_size,
                    "heatmap_stride": heatmap_stride,
                    "consistency_weight": consistency_weight,
                    "best_val_mean_pixel_error": best_val_error,
                    "epochs": epochs,
                    "device": device,
                    "history": history,
                },
            )
        emit_progress(
            "train_epoch",
            epoch=epoch_index + 1,
            total=epochs,
            train_loss=f"{mean_loss:.4f}",
            val_px=f"{metrics['mean_pixel_error']:.2f}",
            best_px=f"{best_val_error:.2f}",
        )

    emit_progress(
        "train_done",
        best_px=f"{best_val_error:.2f}",
        checkpoint=str(checkpoint_path),
    )

    return {
        "checkpoint_path": str(checkpoint_path),
        "metadata_path": str(metadata_path),
        "train_record_count": len(train_records),
        "val_record_count": len(val_records),
        "best_val_mean_pixel_error": best_val_error,
        "device": device,
    }


def load_trained_model(checkpoint_path: Path, device: str):
    torch, _, _, _, _ = _load_torch()
    checkpoint = torch.load(checkpoint_path, map_location=device)
    model = build_bike_keypoint_model(num_keypoints=len(KEYPOINT_NAMES)).to(device)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    return model, int(checkpoint["input_size"]), int(checkpoint["heatmap_stride"])


def evaluate_checkpoint(
    dataset_path: Path,
    checkpoint_path: Path,
    device: str,
) -> Dict[str, Any]:
    records = load_dataset_records(dataset_path)
    model, input_size, heatmap_stride = load_trained_model(checkpoint_path, device=device)
    metrics = evaluate_model_records(model, records, input_size=input_size, heatmap_stride=heatmap_stride, device=device)
    return {
        "dataset_path": str(dataset_path),
        "checkpoint_path": str(checkpoint_path),
        **metrics,
    }


def infer_video(
    video_path: Path,
    checkpoint_path: Path,
    output_path: Path,
    max_samples: int,
    device: str,
) -> Dict[str, Any]:
    cv2, _ = _load_cv2_numpy()
    torch, _, _, _, _ = _load_torch()
    model, input_size, heatmap_stride = load_trained_model(checkpoint_path, device=device)

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Unable to open video: {video_path}")
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 0:
        fps = 30.0
    if total_frames <= 0:
        total_frames = max(1, max_samples)
    target_count = max(24, min(max_samples, total_frames))
    frame_indices = [int(round(index * (total_frames - 1) / max(1, target_count - 1))) for index in range(target_count)]

    samples: List[Dict[str, Any]] = []
    crank_points: List[Dict[str, float]] = []
    bb_points: List[Dict[str, float]] = []
    for sample_id, frame_index in enumerate(frame_indices):
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok or frame is None:
            continue
        height, width = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        letterboxed, transform = letterbox_image(rgb, input_size)
        image_tensor = torch.from_numpy(letterboxed.transpose(2, 0, 1)).float().unsqueeze(0) / 255.0
        image_tensor = image_tensor.to(device)
        with torch.no_grad():
            prediction = torch.sigmoid(model(image_tensor))[0].cpu().numpy()
        points, scores = decode_heatmaps(prediction, heatmap_stride=heatmap_stride)

        keypoints: Dict[str, Dict[str, float]] = {}
        for name, (px, py), score in zip(KEYPOINT_NAMES, points, scores):
            orig_x, orig_y = transform.inverse_point((px, py))
            keypoint = normalize_point({"x": orig_x, "y": orig_y, "confidence": score}, width, height)
            keypoints[name] = keypoint
        bb_points.append(keypoints["bb_center"])
        crank_points.append(keypoints["crank_end"])
        samples.append(
            {
                "id": sample_id,
                "time_seconds": frame_index / fps,
                "keypoints": keypoints,
                "confidence": average(scores),
            }
        )
    cap.release()

    fit = fit_circle_robust(crank_points)
    summary: Dict[str, Any] = {}
    if fit is not None:
        bb_center, radius, _, rms = fit
        summary = {
            "bb_center": bb_center,
            "radius": radius,
            "fit_rms": rms,
        }
    else:
        summary = {
            "bb_center": max(bb_points, key=lambda point: point.get("confidence", 0.0)) if bb_points else None,
            "radius": None,
            "fit_rms": None,
        }

    payload = {
        "schema": DATASET_SCHEMA,
        "backend": "bike_keypoint_selftrain",
        "checkpoint_path": str(checkpoint_path),
        "video_path": str(video_path),
        "samples": samples,
        "summary": summary,
    }
    write_json(output_path, payload)
    return payload


def generate_synthetic_dataset(output_dir: Path, count: int, image_size: int, seed: int) -> Dict[str, Any]:
    cv2, np = _load_cv2_numpy()
    rng = random.Random(seed)
    ensure_dir(output_dir)
    images_dir = output_dir / "images"
    ensure_dir(images_dir)
    records: List[Dict[str, Any]] = []

    for index in range(count):
        width = image_size
        height = image_size
        image = np.full((height, width, 3), 248, dtype=np.uint8)
        center = (rng.randint(width // 3, width * 2 // 3), rng.randint(height // 3, height * 2 // 3))
        radius = rng.randint(width // 7, width // 4)
        phase_deg = rng.uniform(0.0, 360.0)
        radians = math.radians(phase_deg)
        crank_end = (
            center[0] + math.sin(radians) * radius,
            center[1] - math.cos(radians) * radius,
        )
        tangent = (math.cos(radians), math.sin(radians))
        pedal_center = (
            crank_end[0] + tangent[0] * rng.uniform(8.0, 14.0),
            crank_end[1] + tangent[1] * rng.uniform(8.0, 14.0),
        )

        wheel_radius = radius * rng.uniform(1.9, 2.3)
        rear_wheel = (center[0] - radius * rng.uniform(2.4, 3.0), center[1] + rng.uniform(-8.0, 8.0))
        front_wheel = (center[0] + radius * rng.uniform(2.6, 3.2), center[1] + rng.uniform(-8.0, 8.0))

        cv2.circle(image, (int(rear_wheel[0]), int(rear_wheel[1])), int(wheel_radius), (180, 180, 180), 2)
        cv2.circle(image, (int(front_wheel[0]), int(front_wheel[1])), int(wheel_radius), (180, 180, 180), 2)
        cv2.line(image, (int(rear_wheel[0]), int(rear_wheel[1])), center, (70, 120, 90), 4)
        cv2.line(image, center, (int(front_wheel[0]), int(front_wheel[1])), (70, 120, 90), 4)
        cv2.line(image, center, (int(crank_end[0]), int(crank_end[1])), (30, 30, 30), 6)
        cv2.circle(image, center, 8, (40, 120, 255), -1)
        cv2.circle(image, (int(crank_end[0]), int(crank_end[1])), 8, (30, 30, 30), -1)
        pedal_rect = (
            int(pedal_center[0] - 12),
            int(pedal_center[1] - 5),
            24,
            10,
        )
        cv2.rectangle(
            image,
            (pedal_rect[0], pedal_rect[1]),
            (pedal_rect[0] + pedal_rect[2], pedal_rect[1] + pedal_rect[3]),
            (20, 20, 20),
            -1,
        )
        cv2.circle(image, (int(center[0]), int(center[1])), int(radius), (100, 100, 100), 1)

        if rng.random() < 0.5:
            x0 = rng.randint(0, width // 2)
            y0 = rng.randint(0, height // 2)
            x1 = min(width - 1, x0 + rng.randint(width // 8, width // 4))
            y1 = min(height - 1, y0 + rng.randint(height // 8, height // 4))
            cv2.rectangle(image, (x0, y0), (x1, y1), (rng.randint(220, 245),) * 3, -1)

        image_path = images_dir / f"synthetic-{index:04d}.jpg"
        cv2.imwrite(str(image_path), image)
        records.append(
            {
                "id": f"synthetic-{index:04d}",
                "image_path": str(image_path),
                "video_path": "synthetic",
                "time_seconds": float(index),
                "width": width,
                "height": height,
                "side": "right",
                "quality": 1.0,
                "source": "synthetic",
                "keypoints": {
                    "bb_center": normalize_point({"x": center[0], "y": center[1], "confidence": 1.0}, width, height),
                    "crank_end": normalize_point({"x": crank_end[0], "y": crank_end[1], "confidence": 1.0}, width, height),
                    "pedal_center": normalize_point({"x": pedal_center[0], "y": pedal_center[1], "confidence": 1.0}, width, height),
                },
            }
        )

    dataset_path = output_dir / "dataset.json"
    payload = build_dataset_payload(records, source_videos=[])
    write_json(dataset_path, payload)
    return {
        "dataset_path": str(dataset_path),
        "record_count": len(records),
        "output_dir": str(output_dir),
    }


def command_pseudo_label(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir).expanduser()
    ensure_dir(output_dir)
    python_executable = resolve_pose_python(args.python)
    videos = collect_video_paths(args.inputs)
    if not videos:
        raise RuntimeError("No videos found for pseudo-label generation.")

    emit_progress("pseudo_prepare", video_count=len(videos), max_samples=args.max_samples)

    all_records: List[Dict[str, Any]] = []
    video_summaries: List[Dict[str, Any]] = []
    for video_index, video_path in enumerate(videos, start=1):
        emit_progress(
            "pseudo_video",
            index=video_index,
            total=len(videos),
            name=video_path.name,
        )
        video_output_dir = output_dir / video_path.stem
        ensure_dir(video_output_dir)
        summary = extract_pseudo_labels_for_video(
            video_path=video_path,
            output_dir=video_output_dir,
            max_samples=args.max_samples,
            python_executable=python_executable,
            min_quality=args.min_quality,
        )
        all_records.extend(summary["records"])
        video_summaries.append({key: value for key, value in summary.items() if key != "records"})
        emit_progress(
            "pseudo_video_done",
            index=video_index,
            total=len(videos),
            name=video_path.name,
            records=summary["record_count"],
        )

    dataset_payload = build_dataset_payload(all_records, source_videos=videos)
    dataset_payload["videos"] = video_summaries
    dataset_path = output_dir / "dataset.json"
    write_json(dataset_path, dataset_payload)
    emit_progress(
        "pseudo_done",
        dataset_path=str(dataset_path),
        record_count=len(all_records),
        video_count=len(videos),
    )
    print(json.dumps({"dataset_path": str(dataset_path), "record_count": len(all_records), "video_count": len(videos)}, ensure_ascii=False))
    return 0


def command_train(args: argparse.Namespace) -> int:
    summary = train_model(
        dataset_path=Path(args.dataset).expanduser(),
        output_dir=Path(args.output_dir).expanduser(),
        epochs=args.epochs,
        batch_size=args.batch_size,
        input_size=args.image_size,
        heatmap_stride=args.heatmap_stride,
        learning_rate=args.learning_rate,
        weight_decay=args.weight_decay,
        val_ratio=args.val_ratio,
        consistency_weight=args.consistency_weight,
        seed=args.seed,
        device=resolve_training_device(args.device),
        workers=args.workers,
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


def command_evaluate(args: argparse.Namespace) -> int:
    summary = evaluate_checkpoint(
        dataset_path=Path(args.dataset).expanduser(),
        checkpoint_path=Path(args.checkpoint).expanduser(),
        device=resolve_training_device(args.device),
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


def command_infer_video(args: argparse.Namespace) -> int:
    summary = infer_video(
        video_path=Path(args.video).expanduser(),
        checkpoint_path=Path(args.checkpoint).expanduser(),
        output_path=Path(args.output).expanduser(),
        max_samples=args.max_samples,
        device=resolve_training_device(args.device),
    )
    print(json.dumps({"output_path": str(args.output), "sample_count": len(summary["samples"])}, ensure_ascii=False))
    return 0


def command_synthetic_dataset(args: argparse.Namespace) -> int:
    summary = generate_synthetic_dataset(
        output_dir=Path(args.output_dir).expanduser(),
        count=args.count,
        image_size=args.image_size,
        seed=args.seed,
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Self-training pipeline for road-bike component keypoints.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    pseudo = subparsers.add_parser("pseudo-label", help="Generate pseudo labels from cycling videos.")
    pseudo.add_argument("inputs", nargs="+", help="Video files or directories of videos.")
    pseudo.add_argument("--output-dir", required=True)
    pseudo.add_argument("--python", default=None, help="Python executable that can run MediaPipe pose inference.")
    pseudo.add_argument("--max-samples", type=int, default=180)
    pseudo.add_argument("--min-quality", type=float, default=0.45)
    pseudo.set_defaults(func=command_pseudo_label)

    synthetic = subparsers.add_parser("synthetic-dataset", help="Generate a tiny synthetic bike-keypoint dataset.")
    synthetic.add_argument("--output-dir", required=True)
    synthetic.add_argument("--count", type=int, default=24)
    synthetic.add_argument("--image-size", type=int, default=DEFAULT_INPUT_SIZE)
    synthetic.add_argument("--seed", type=int, default=13)
    synthetic.set_defaults(func=command_synthetic_dataset)

    train = subparsers.add_parser("train", help="Train the compact bike-keypoint model.")
    train.add_argument("--dataset", required=True)
    train.add_argument("--output-dir", required=True)
    train.add_argument("--epochs", type=int, default=8)
    train.add_argument("--batch-size", type=int, default=8)
    train.add_argument("--image-size", type=int, default=DEFAULT_INPUT_SIZE)
    train.add_argument("--heatmap-stride", type=int, default=DEFAULT_HEATMAP_STRIDE)
    train.add_argument("--learning-rate", type=float, default=3e-4)
    train.add_argument("--weight-decay", type=float, default=1e-4)
    train.add_argument("--val-ratio", type=float, default=0.2)
    train.add_argument("--consistency-weight", type=float, default=0.15)
    train.add_argument("--seed", type=int, default=13)
    train.add_argument("--device", default=None)
    train.add_argument("--workers", type=int, default=0)
    train.set_defaults(func=command_train)

    evaluate = subparsers.add_parser("evaluate", help="Evaluate a trained checkpoint against a dataset.")
    evaluate.add_argument("--dataset", required=True)
    evaluate.add_argument("--checkpoint", required=True)
    evaluate.add_argument("--device", default=None)
    evaluate.set_defaults(func=command_evaluate)

    infer = subparsers.add_parser("infer-video", help="Run a trained checkpoint on a video.")
    infer.add_argument("--video", required=True)
    infer.add_argument("--checkpoint", required=True)
    infer.add_argument("--output", required=True)
    infer.add_argument("--max-samples", type=int, default=180)
    infer.add_argument("--device", default=None)
    infer.set_defaults(func=command_infer_video)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
