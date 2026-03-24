#!/usr/bin/env python3
import argparse
import json
import math
import os
import sys


MOTIONBERT_ALIAS = "motionbert_dstformer-ft-243frm_8xb32-120e_h36m"
H36M = {
    "right_hip": 1,
    "right_knee": 2,
    "right_ankle": 3,
    "left_hip": 4,
    "left_knee": 5,
    "left_ankle": 6,
    "left_shoulder": 11,
    "right_shoulder": 14,
}


def _load_dependencies():
    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
        from mmpose.apis import MMPoseInferencer  # type: ignore

        return cv2, np, MMPoseInferencer
    except Exception as exc:  # pragma: no cover - runtime dependency
        raise RuntimeError(f"Missing dependency: {exc}") from exc


def _angle_3d(a, b, c):
    bax = a[0] - b[0]
    bay = a[1] - b[1]
    baz = a[2] - b[2]
    bcx = c[0] - b[0]
    bcy = c[1] - b[1]
    bcz = c[2] - b[2]
    dot = bax * bcx + bay * bcy + baz * bcz
    mag_ba = math.sqrt(bax * bax + bay * bay + baz * baz)
    mag_bc = math.sqrt(bcx * bcx + bcy * bcy + bcz * bcz)
    if mag_ba < 1e-8 or mag_bc < 1e-8:
        return None
    cosine = max(-1.0, min(1.0, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cosine))


def _as_instances(result):
    predictions = result.get("predictions")
    if not isinstance(predictions, list) or not predictions:
        return []
    if isinstance(predictions[0], list):
        return [item for item in predictions[0] if isinstance(item, dict)]
    return [item for item in predictions if isinstance(item, dict)]


def _mean_score(instance, np_module):
    for key in ("keypoint_scores", "keypoints_visible", "scores"):
        raw = instance.get(key)
        if raw is None:
            continue
        arr = np_module.asarray(raw, dtype=float).reshape(-1)
        finite = arr[np_module.isfinite(arr)]
        if finite.size > 0:
            return float(finite.mean())
    return 0.0


def _extract_keypoints_3d(instance, np_module):
    for key in ("keypoints", "keypoints_3d"):
        raw = instance.get(key)
        if raw is None:
            continue
        arr = np_module.asarray(raw, dtype=float)
        if arr.ndim == 3:
            arr = arr[0]
        if arr.ndim != 2 or arr.shape[0] < 17 or arr.shape[1] < 3:
            continue
        return arr
    return None


def _pick_best_instance(instances, np_module):
    if not instances:
        return None
    return max(instances, key=lambda item: _mean_score(item, np_module))


def _compute_angles(points3d):
    left_knee = _angle_3d(
        points3d[H36M["left_hip"]],
        points3d[H36M["left_knee"]],
        points3d[H36M["left_ankle"]],
    )
    left_hip = _angle_3d(
        points3d[H36M["left_shoulder"]],
        points3d[H36M["left_hip"]],
        points3d[H36M["left_knee"]],
    )
    right_knee = _angle_3d(
        points3d[H36M["right_hip"]],
        points3d[H36M["right_knee"]],
        points3d[H36M["right_ankle"]],
    )
    right_hip = _angle_3d(
        points3d[H36M["right_shoulder"]],
        points3d[H36M["right_hip"]],
        points3d[H36M["right_knee"]],
    )
    return left_knee, left_hip, right_knee, right_hip


def _subsample(samples, max_samples, np_module):
    if len(samples) <= max_samples:
        return samples
    indices = np_module.linspace(0, len(samples) - 1, num=max_samples, dtype=int).tolist()
    return [samples[index] for index in indices]


def run(video_path: str, max_samples: int):
    cv2, np, MMPoseInferencer = _load_dependencies()

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError("Unable to open video file.")

    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 0:
        fps = 30.0
    cap.release()

    device = os.environ.get("FRICU_MMPPOSE_DEVICE", "cpu")
    inferencer = MMPoseInferencer(
        pose3d=MOTIONBERT_ALIAS,
        device=device,
        det_model="whole_image",
    )

    samples = []
    dropped_frames = 0
    low_confidence_frames = 0

    generator = inferencer(
        video_path,
        return_vis=False,
        show=False,
        num_instances=1,
    )

    for frame_index, result in enumerate(generator):
        instance = _pick_best_instance(_as_instances(result), np)
        if instance is None:
            dropped_frames += 1
            continue

        keypoints3d = _extract_keypoints_3d(instance, np)
        if keypoints3d is None:
            dropped_frames += 1
            continue

        confidence = _mean_score(instance, np)
        if confidence < 0.45:
            low_confidence_frames += 1

        left_knee, left_hip, right_knee, right_hip = _compute_angles(keypoints3d)
        if all(value is None for value in (left_knee, left_hip, right_knee, right_hip)):
            dropped_frames += 1
            continue

        samples.append(
            {
                "time_seconds": float(frame_index / fps),
                "left_knee_angle_deg": left_knee,
                "left_hip_angle_deg": left_hip,
                "right_knee_angle_deg": right_knee,
                "right_hip_angle_deg": right_hip,
                "confidence": float(confidence),
            }
        )

    samples = _subsample(samples, max(24, int(max_samples)), np)

    warnings = []
    if not samples:
        warnings.append("No usable MotionBERT 3D angle frames were returned by MMPose.")
    else:
        low_ratio = low_confidence_frames / float(max(1, len(samples)))
        if low_ratio > 0.35:
            warnings.append(
                "MotionBERT confidence is low on many frames. Improve lighting, keep the rider fully visible, and reduce blur."
            )
        if dropped_frames > len(samples):
            warnings.append(
                "Many frames were skipped during MotionBERT 3D inference. A stable full-body side view generally works best."
            )

    return {
        "backend": "mmpose_motionbert",
        "samples": samples,
        "warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True)
    parser.add_argument("--max-samples", type=int, default=180)
    args = parser.parse_args()

    try:
        payload = run(args.video, args.max_samples)
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:  # pragma: no cover - runtime dependency
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
