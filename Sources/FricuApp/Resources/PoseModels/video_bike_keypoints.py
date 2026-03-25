#!/usr/bin/env python3
"""Infer road-bike BB / crank / pedal keypoints from a side-view cycling video."""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


KEYPOINT_NAMES = ("bb_center", "crank_end", "pedal_center")


def _load_cv2_numpy():
    import cv2  # type: ignore
    import numpy as np  # type: ignore

    return cv2, np


def _load_torch():
    import torch
    import torch.nn as nn

    return torch, nn


def emit_progress(stage: str, **fields: object) -> None:
    suffix = "".join(f"|{key}={value}" for key, value in fields.items())
    print(f"FRICU_PROGRESS|{stage}{suffix}", file=sys.stderr, flush=True)


def resolve_device(explicit: Optional[str] = None) -> str:
    if explicit:
        return explicit
    explicit_env = os.environ.get("FRICU_BIKE_KEYPOINT_DEVICE") or os.environ.get("FRICU_MMPPOSE_DEVICE")
    if explicit_env:
        return explicit_env
    torch, _ = _load_torch()
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def build_model(num_keypoints: int):
    torch, nn = _load_torch()

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


def letterbox_image(image, output_size: int):
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
    return canvas, (scale, pad_x, pad_y)


def inverse_letterbox(point_xy: Tuple[float, float], transform: Tuple[float, int, int]) -> Tuple[float, float]:
    scale, pad_x, pad_y = transform
    x, y = point_xy
    safe_scale = max(scale, 1e-8)
    return (x - pad_x) / safe_scale, (y - pad_y) / safe_scale


def normalize_point(point: Dict[str, float], width: int, height: int) -> Dict[str, float]:
    return {
        "x": float(point["x"]) / float(max(1, width)),
        "y": float(point["y"]) / float(max(1, height)),
        "confidence": float(point.get("confidence", 0.0)),
    }


def solve_circle(points: Sequence[Dict[str, float]]) -> Optional[Tuple[float, float, float]]:
    _, np = _load_cv2_numpy()
    if len(points) < 3:
        return None
    coords = np.array([[float(point["x"]), float(point["y"])] for point in points], dtype=np.float64)
    x = coords[:, 0]
    y = coords[:, 1]
    a = np.column_stack((2.0 * x, 2.0 * y, np.ones(len(coords), dtype=np.float64)))
    b = x * x + y * y
    solution, _, rank, _ = np.linalg.lstsq(a, b, rcond=None)
    if rank < 3:
        return None
    center_x = float(solution[0])
    center_y = float(solution[1])
    radius_sq = float(solution[2] + center_x * center_x + center_y * center_y)
    if not math.isfinite(radius_sq) or radius_sq <= 0:
        return None
    return center_x, center_y, math.sqrt(radius_sq)


def fit_circle_robust(points: Sequence[Dict[str, float]]) -> Optional[Tuple[Dict[str, float], float, float]]:
    if len(points) < 6:
        return None
    initial = solve_circle(points)
    if initial is None:
        return None
    center_x, center_y, radius = initial
    residuals = [abs(math.hypot(point["x"] - center_x, point["y"] - center_y) - radius) for point in points]
    sorted_residuals = sorted(residuals)
    median_residual = sorted_residuals[len(sorted_residuals) // 2]
    threshold = max(0.015, radius * 0.18, median_residual * 2.5)
    inliers = [point for point, residual in zip(points, residuals) if residual <= threshold]
    if len(inliers) < 6:
        return None
    refined = solve_circle(inliers)
    if refined is None:
        return None
    center_x, center_y, radius = refined
    rms = math.sqrt(
        sum((math.hypot(point["x"] - center_x, point["y"] - center_y) - radius) ** 2 for point in inliers)
        / float(len(inliers))
    )
    confidence = sum(float(point.get("confidence", 0.0)) for point in inliers) / float(len(inliers))
    return {"x": center_x, "y": center_y, "confidence": confidence}, radius, rms


def decode_heatmaps(heatmaps, heatmap_stride: int) -> Tuple[List[Tuple[float, float]], List[float]]:
    _, np = _load_cv2_numpy()
    channels, _, width = heatmaps.shape
    points: List[Tuple[float, float]] = []
    scores: List[float] = []
    for index in range(channels):
        heatmap = heatmaps[index]
        flat_index = int(np.argmax(heatmap))
        y, x = divmod(flat_index, width)
        points.append(((x + 0.5) * heatmap_stride, (y + 0.5) * heatmap_stride))
        scores.append(float(heatmap[y, x]))
    return points, scores


def load_model(checkpoint_path: Path, device: str):
    torch, _ = _load_torch()
    emit_progress("loading_model", device=device)
    checkpoint = torch.load(checkpoint_path, map_location=device)
    model = build_model(num_keypoints=len(KEYPOINT_NAMES)).to(device)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    emit_progress("model_ready")
    return model, int(checkpoint["input_size"]), int(checkpoint["heatmap_stride"])


def infer_video(video_path: Path, checkpoint_path: Path, max_samples: int, device: str) -> Dict[str, object]:
    cv2, _ = _load_cv2_numpy()
    torch, _ = _load_torch()

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
    frame_indices = [
        int(round(index * (total_frames - 1) / max(1, target_count - 1)))
        for index in range(target_count)
    ]

    emit_progress("prepare", target_frames=target_count, device=device)
    model, input_size, heatmap_stride = load_model(checkpoint_path, device=device)

    samples: List[Dict[str, object]] = []
    crank_end_points: List[Dict[str, float]] = []
    bb_points: List[Dict[str, float]] = []
    usable = 0
    dropped = 0
    step = max(1, target_count // 8)
    for sample_id, frame_index in enumerate(frame_indices):
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok or frame is None:
            dropped += 1
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
        for name, (pixel_x, pixel_y), score in zip(KEYPOINT_NAMES, points, scores):
            original_x, original_y = inverse_letterbox((pixel_x, pixel_y), transform)
            normalized = normalize_point(
                {"x": original_x, "y": original_y, "confidence": score},
                width,
                height,
            )
            keypoints[name] = normalized

        bb_points.append(keypoints["bb_center"])
        crank_end_points.append(keypoints["crank_end"])
        samples.append(
            {
                "id": sample_id,
                "time_seconds": frame_index / fps,
                "keypoints": keypoints,
                "confidence": sum(scores) / float(max(1, len(scores))),
            }
        )
        usable += 1
        completed = sample_id + 1
        if completed == 1 or completed == target_count or completed % step == 0:
            emit_progress("frame", completed=completed, total=target_count)

    cap.release()

    fit = fit_circle_robust(crank_end_points)
    if fit is not None:
        bb_center, radius, rms = fit
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

    emit_progress("complete", usable=usable, total=target_count, dropped=dropped)
    return {
        "backend": "bike_keypoint_selftrain",
        "checkpoint_path": str(checkpoint_path),
        "video_path": str(video_path),
        "samples": samples,
        "summary": summary,
        "warnings": [],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Infer road-bike BB / crank / pedal keypoints.")
    parser.add_argument("--video", required=True)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--max-samples", type=int, default=180)
    parser.add_argument("--device", default=None)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    payload = infer_video(
        video_path=Path(args.video).expanduser(),
        checkpoint_path=Path(args.checkpoint).expanduser(),
        max_samples=args.max_samples,
        device=resolve_device(args.device),
    )
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
