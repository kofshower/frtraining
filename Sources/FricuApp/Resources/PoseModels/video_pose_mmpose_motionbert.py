#!/usr/bin/env python3
import argparse
import contextlib
import json
import math
import os
import sys
from pathlib import Path


MODEL_FRAME_COUNT = 243
DEFAULT_TARGET_FPS = 20.0
MODEL_CHECKPOINT_NAME = "motionagformer-l-h36m.pth.tr"
PROGRESS_PREFIX = "FRICU_PROGRESS"
H36M = {
    "pelvis": 0,
    "right_hip": 1,
    "right_knee": 2,
    "right_ankle": 3,
    "left_hip": 4,
    "left_knee": 5,
    "left_ankle": 6,
    "spine": 7,
    "thorax": 8,
    "nose": 9,
    "head": 10,
    "left_shoulder": 11,
    "left_elbow": 12,
    "left_wrist": 13,
    "right_shoulder": 14,
    "right_elbow": 15,
    "right_wrist": 16,
}


def _resolve_runtime_root():
    executable = Path(sys.executable).resolve()
    if executable.parent.name == "bin":
        return executable.parent.parent
    return executable.parent


def _resolve_motionagformer_repo_root():
    explicit = os.environ.get("FRICU_MOTIONAGFORMER_REPO", "").strip()
    candidates = [Path(explicit)] if explicit else []
    runtime_root = _resolve_runtime_root()
    candidates.extend(
        [
            runtime_root / "vendor" / "MotionAGFormer",
            Path.cwd() / ".runtime" / "MotionBERTRuntime" / "vendor" / "MotionAGFormer",
            Path.home() / "miniconda3" / "envs" / "mmpose-mac" / "vendor" / "MotionAGFormer",
        ]
    )
    for candidate in candidates:
        if candidate.is_dir() and (candidate / "model" / "MotionAGFormer.py").exists():
            return candidate
    return None


def _resolve_checkpoint_path():
    explicit = os.environ.get("FRICU_MOTIONAGFORMER_CHECKPOINT", "").strip()
    candidates = [Path(explicit)] if explicit else []
    runtime_root = _resolve_runtime_root()
    candidates.extend(
        [
            runtime_root / "checkpoints" / MODEL_CHECKPOINT_NAME,
            runtime_root / "vendor" / "MotionAGFormer" / "checkpoint" / MODEL_CHECKPOINT_NAME,
            Path.cwd() / ".runtime" / "MotionBERTRuntime" / "checkpoints" / MODEL_CHECKPOINT_NAME,
            Path.home() / "miniconda3" / "envs" / "mmpose-mac" / "checkpoints" / MODEL_CHECKPOINT_NAME,
        ]
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise RuntimeError(
        "MotionAGFormer-L checkpoint not found. Set FRICU_MOTIONAGFORMER_CHECKPOINT or place "
        f"{MODEL_CHECKPOINT_NAME} under the bundled runtime checkpoints directory."
    )


def _load_dependencies():
    try:
        import cv2  # type: ignore
        import mediapipe as mp  # type: ignore
        import numpy as np  # type: ignore
        import torch  # type: ignore
    except Exception as exc:  # pragma: no cover - runtime dependency
        raise RuntimeError(f"Missing dependency: {exc}") from exc

    repo_root = _resolve_motionagformer_repo_root()
    if repo_root is None:
        raise RuntimeError(
            "MotionAGFormer repo not found inside the current Python runtime. "
            "Expected vendor/MotionAGFormer beside the bundled runtime."
        )

    repo_root_path = str(repo_root)
    if repo_root_path not in sys.path:
        sys.path.insert(0, repo_root_path)

    try:
        from model.MotionAGFormer import MotionAGFormer  # type: ignore
    except Exception as exc:  # pragma: no cover - runtime dependency
        raise RuntimeError(f"Unable to import MotionAGFormer: {exc}") from exc

    return cv2, mp, np, torch, MotionAGFormer


def _joint_from_landmark(landmark):
    return {
        "x": float(landmark.x),
        "y": float(landmark.y),
        "confidence": float(getattr(landmark, "visibility", 0.0)),
    }


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


def _angle_2d(a, b, c):
    bax = a["x"] - b["x"]
    bay = a["y"] - b["y"]
    bcx = c["x"] - b["x"]
    bcy = c["y"] - b["y"]
    dot = bax * bcx + bay * bcy
    mag_ba = math.sqrt(bax * bax + bay * bay)
    mag_bc = math.sqrt(bcx * bcx + bcy * bcy)
    if mag_ba < 1e-8 or mag_bc < 1e-8:
        return None
    cosine = max(-1.0, min(1.0, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cosine))


def _mean_joint(a, b):
    if a is None or b is None:
        return None
    return {
        "x": (a["x"] + b["x"]) / 2.0,
        "y": (a["y"] + b["y"]) / 2.0,
        "confidence": min(a["confidence"], b["confidence"]),
    }


def _compute_angles(points3d):
    left_knee = _angle_3d(
        points3d[H36M["left_hip"]],
        points3d[H36M["left_knee"]],
        points3d[H36M["left_ankle"]],
    )
    right_knee = _angle_3d(
        points3d[H36M["right_hip"]],
        points3d[H36M["right_knee"]],
        points3d[H36M["right_ankle"]],
    )
    return left_knee, right_knee


def _target_frame_indices(total_frames, fps, max_samples, np_module):
    duration_seconds = total_frames / max(fps, 1e-6)
    target_fps = float(os.environ.get("FRICU_MMPPOSE_TARGET_FPS", str(DEFAULT_TARGET_FPS)) or DEFAULT_TARGET_FPS)
    duration_limited_count = max(24, int(round(duration_seconds * max(1.0, target_fps))))
    target_count = max(24, min(int(max_samples), max(1, total_frames), duration_limited_count))
    if total_frames <= 1:
        return [0]
    return np_module.linspace(0, total_frames - 1, num=target_count, dtype=int).tolist()


def _emit_progress(stage, **fields):
    payload = [PROGRESS_PREFIX, stage]
    for key, value in fields.items():
        payload.append(f"{key}={value}")
    print("|".join(payload), file=sys.stderr, flush=True)


def _resolve_device():
    explicit = os.environ.get("FRICU_MMPPOSE_DEVICE", "").strip()
    if explicit:
        return explicit

    try:
        import torch  # type: ignore
    except Exception:
        return "cpu"

    mps_backend = getattr(getattr(torch, "backends", None), "mps", None)
    if mps_backend is not None and getattr(mps_backend, "is_available", lambda: False)():
        return "mps"
    if getattr(getattr(torch, "cuda", None), "is_available", lambda: False)():
        return "cuda"
    return "cpu"


def _normalize_screen_coordinates(X, w, h, np_module):
    result = np_module.copy(X)
    result[..., :2] = X[..., :2] / w * 2 - np_module.array([1.0, h / w], dtype=np_module.float32)
    return result


def _flip_data(data, np_module):
    flipped = np_module.copy(data)
    flipped[..., 0] *= -1
    left_joints = [1, 2, 3, 14, 15, 16]
    right_joints = [4, 5, 6, 11, 12, 13]
    flipped[..., left_joints + right_joints, :] = flipped[..., right_joints + left_joints, :]
    return flipped


def _resample_indices(count, target_count, np_module):
    if count <= 1:
        return [0] * target_count
    return np_module.linspace(0, count - 1, num=target_count, dtype=int).tolist()


def _build_h36m_keypoints(joints):
    pelvis = _mean_joint(joints.get("left_hip"), joints.get("right_hip"))
    thorax = _mean_joint(joints.get("left_shoulder"), joints.get("right_shoulder"))
    spine = _mean_joint(pelvis, thorax)
    head = _mean_joint(joints.get("left_eye"), joints.get("right_eye")) or joints.get("nose")

    mapping = {
        H36M["pelvis"]: pelvis,
        H36M["right_hip"]: joints.get("right_hip"),
        H36M["right_knee"]: joints.get("right_knee"),
        H36M["right_ankle"]: joints.get("right_ankle"),
        H36M["left_hip"]: joints.get("left_hip"),
        H36M["left_knee"]: joints.get("left_knee"),
        H36M["left_ankle"]: joints.get("left_ankle"),
        H36M["spine"]: spine,
        H36M["thorax"]: thorax,
        H36M["nose"]: joints.get("nose"),
        H36M["head"]: head,
        H36M["left_shoulder"]: joints.get("left_shoulder"),
        H36M["left_elbow"]: joints.get("left_elbow"),
        H36M["left_wrist"]: joints.get("left_wrist"),
        H36M["right_shoulder"]: joints.get("right_shoulder"),
        H36M["right_elbow"]: joints.get("right_elbow"),
        H36M["right_wrist"]: joints.get("right_wrist"),
    }

    points = []
    for index in range(17):
        point = mapping.get(index)
        if point is None:
            points.append([0.0, 0.0, 0.0])
        else:
            points.append([point["x"], point["y"], point["confidence"]])
    return points


def _load_model(torch_module, MotionAGFormer):
    model = MotionAGFormer(
        n_layers=26,
        dim_in=3,
        dim_feat=128,
        dim_rep=512,
        dim_out=3,
        mlp_ratio=4,
        attn_drop=0.0,
        drop=0.0,
        drop_path=0.0,
        use_layer_scale=True,
        layer_scale_init_value=0.00001,
        use_adaptive_fusion=True,
        num_heads=8,
        qkv_bias=False,
        qkv_scale=None,
        hierarchical=False,
        use_temporal_similarity=True,
        neighbour_num=2,
        temporal_connection_len=1,
        use_tcn=False,
        graph_only=False,
        n_frames=MODEL_FRAME_COUNT,
    )
    checkpoint = torch_module.load(
        str(_resolve_checkpoint_path()),
        map_location="cpu",
        weights_only=False,
    )
    state = checkpoint.get("model", checkpoint)
    cleaned_state = {}
    for key, value in state.items():
        cleaned_state[key.removeprefix("module.")] = value
    model.load_state_dict(cleaned_state, strict=True)
    return model


def run(video_path: str, max_samples: int):
    cv2, mp, np, torch, MotionAGFormer = _load_dependencies()

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError("Unable to open video file.")

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    width = float(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0.0)
    height = float(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0.0)
    if fps <= 0:
        fps = 30.0
    if total_frames <= 0:
        total_frames = max(1, int(cap.get(cv2.CAP_PROP_POS_FRAMES) or 1))

    frame_indices = _target_frame_indices(total_frames, fps, max_samples, np)
    device = _resolve_device()
    _emit_progress("prepare", device=device, target_frames=len(frame_indices))

    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(
        static_image_mode=True,
        model_complexity=2,
        smooth_landmarks=False,
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    lm_idx = {
        "nose": mp_pose.PoseLandmark.NOSE.value,
        "left_eye": mp_pose.PoseLandmark.LEFT_EYE.value,
        "right_eye": mp_pose.PoseLandmark.RIGHT_EYE.value,
        "left_shoulder": mp_pose.PoseLandmark.LEFT_SHOULDER.value,
        "right_shoulder": mp_pose.PoseLandmark.RIGHT_SHOULDER.value,
        "left_elbow": mp_pose.PoseLandmark.LEFT_ELBOW.value,
        "right_elbow": mp_pose.PoseLandmark.RIGHT_ELBOW.value,
        "left_wrist": mp_pose.PoseLandmark.LEFT_WRIST.value,
        "right_wrist": mp_pose.PoseLandmark.RIGHT_WRIST.value,
        "left_hip": mp_pose.PoseLandmark.LEFT_HIP.value,
        "right_hip": mp_pose.PoseLandmark.RIGHT_HIP.value,
        "left_knee": mp_pose.PoseLandmark.LEFT_KNEE.value,
        "right_knee": mp_pose.PoseLandmark.RIGHT_KNEE.value,
        "left_ankle": mp_pose.PoseLandmark.LEFT_ANKLE.value,
        "right_ankle": mp_pose.PoseLandmark.RIGHT_ANKLE.value,
        "left_foot_index": mp_pose.PoseLandmark.LEFT_FOOT_INDEX.value,
        "right_foot_index": mp_pose.PoseLandmark.RIGHT_FOOT_INDEX.value,
    }

    detections = []
    dropped_frames = 0
    low_confidence_frames = 0
    current_frame_index = 0
    total_targets = len(frame_indices)
    progress_every = max(1, total_targets // 10)

    for processed_count, frame_index in enumerate(frame_indices, start=1):
        while current_frame_index < frame_index:
            if not cap.grab():
                cap.release()
                raise RuntimeError("Unable to advance to the requested video frame.")
            current_frame_index += 1

        ok, frame = cap.read()
        if not ok or frame is None:
            dropped_frames += 1
            _emit_progress("frame", completed=processed_count, total=total_targets)
            break
        current_frame_index += 1

        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = pose.process(frame_rgb)
        if not result.pose_landmarks:
            dropped_frames += 1
            if processed_count == 1 or processed_count == total_targets or processed_count % progress_every == 0:
                _emit_progress("frame", completed=processed_count, total=total_targets)
            continue

        landmarks = result.pose_landmarks.landmark
        joints = {}
        confidence_values = []
        for key, index in lm_idx.items():
            if index < 0 or index >= len(landmarks):
                continue
            joint = _joint_from_landmark(landmarks[index])
            joints[key] = joint
            confidence_values.append(joint["confidence"])

        if len(joints) < 12:
            dropped_frames += 1
            if processed_count == 1 or processed_count == total_targets or processed_count % progress_every == 0:
                _emit_progress("frame", completed=processed_count, total=total_targets)
            continue

        confidence = sum(confidence_values) / max(1, len(confidence_values))
        if confidence < 0.45:
            low_confidence_frames += 1

        left_hip_angle_deg = None
        right_hip_angle_deg = None
        left_ankle_angle_deg = None
        right_ankle_angle_deg = None
        if {"left_shoulder", "left_hip", "left_knee"}.issubset(joints):
            left_hip_angle_deg = _angle_2d(
                joints["left_shoulder"],
                joints["left_hip"],
                joints["left_knee"],
            )
        if {"right_shoulder", "right_hip", "right_knee"}.issubset(joints):
            right_hip_angle_deg = _angle_2d(
                joints["right_shoulder"],
                joints["right_hip"],
                joints["right_knee"],
            )
        if result.pose_world_landmarks:
            world = result.pose_world_landmarks.landmark
            try:
                left_ankle_angle_deg = _angle_3d(
                    [world[lm_idx["left_knee"]].x, world[lm_idx["left_knee"]].y, world[lm_idx["left_knee"]].z],
                    [world[lm_idx["left_ankle"]].x, world[lm_idx["left_ankle"]].y, world[lm_idx["left_ankle"]].z],
                    [world[lm_idx["left_foot_index"]].x, world[lm_idx["left_foot_index"]].y, world[lm_idx["left_foot_index"]].z],
                )
                right_ankle_angle_deg = _angle_3d(
                    [world[lm_idx["right_knee"]].x, world[lm_idx["right_knee"]].y, world[lm_idx["right_knee"]].z],
                    [world[lm_idx["right_ankle"]].x, world[lm_idx["right_ankle"]].y, world[lm_idx["right_ankle"]].z],
                    [world[lm_idx["right_foot_index"]].x, world[lm_idx["right_foot_index"]].y, world[lm_idx["right_foot_index"]].z],
                )
            except Exception:
                left_ankle_angle_deg = None
                right_ankle_angle_deg = None

        if left_ankle_angle_deg is None and {"left_knee", "left_ankle", "left_foot_index"}.issubset(joints):
            left_ankle_angle_deg = _angle_2d(
                joints["left_knee"],
                joints["left_ankle"],
                joints["left_foot_index"],
            )
        if right_ankle_angle_deg is None and {"right_knee", "right_ankle", "right_foot_index"}.issubset(joints):
            right_ankle_angle_deg = _angle_2d(
                joints["right_knee"],
                joints["right_ankle"],
                joints["right_foot_index"],
            )

        detections.append(
            {
                "time_seconds": float(frame_index / fps),
                "confidence": float(confidence),
                "left_hip_angle_deg": left_hip_angle_deg,
                "right_hip_angle_deg": right_hip_angle_deg,
                "left_ankle_angle_deg": left_ankle_angle_deg,
                "right_ankle_angle_deg": right_ankle_angle_deg,
                "h36m": _build_h36m_keypoints(joints),
            }
        )

        if processed_count == 1 or processed_count == total_targets or processed_count % progress_every == 0:
            _emit_progress("frame", completed=processed_count, total=total_targets)

    cap.release()
    pose.close()

    if not detections:
        _emit_progress("complete", total=total_targets, usable=0, dropped=dropped_frames)
        return {
            "backend": "motionagformer_l_mediapipe",
            "samples": [],
            "warnings": ["No usable 2D pose frames were returned for MotionAGFormer-L."],
        }

    if width <= 0 or height <= 0:
        probe = cv2.VideoCapture(video_path)
        ok, frame = probe.read()
        probe.release()
        if not ok or frame is None:
            raise RuntimeError("Unable to determine video size for MotionAGFormer-L inference.")
        height, width = frame.shape[0], frame.shape[1]

    _emit_progress("loading_model", device=device)
    model = _load_model(torch, MotionAGFormer)
    _emit_progress("model_ready", device=device, target_frames=len(detections))

    base_sequence = np.asarray([item["h36m"] for item in detections], dtype=np.float32)
    model_indices = _resample_indices(len(detections), MODEL_FRAME_COUNT, np)
    model_sequence = base_sequence[model_indices]
    model_sequence = _normalize_screen_coordinates(model_sequence, width, height, np)

    torch_device = torch.device(device)
    model = model.to(torch_device).eval()
    input_2d = torch.from_numpy(model_sequence).unsqueeze(0).to(torch_device)
    input_2d_flip = torch.from_numpy(_flip_data(model_sequence, np)).unsqueeze(0).to(torch_device)
    with torch.no_grad():
        predicted = model(input_2d).detach().cpu().numpy()
        predicted_flip = _flip_data(model(input_2d_flip).detach().cpu().numpy(), np)
        predicted = (predicted + predicted_flip) / 2.0

    grouped_predictions = {}
    for output_index, source_index in enumerate(model_indices):
        grouped_predictions.setdefault(int(source_index), []).append(predicted[0, output_index])

    samples = []
    for source_index in sorted(grouped_predictions):
        pose3d = np.mean(np.asarray(grouped_predictions[source_index], dtype=np.float32), axis=0)
        left_knee, right_knee = _compute_angles(pose3d)
        detection = detections[source_index]
        if all(
            value is None
            for value in (
                left_knee,
                detection["left_hip_angle_deg"],
                detection["left_ankle_angle_deg"],
                right_knee,
                detection["right_hip_angle_deg"],
                detection["right_ankle_angle_deg"],
            )
        ):
            continue
        samples.append(
            {
                "time_seconds": detection["time_seconds"],
                "left_knee_angle_deg": left_knee,
                "left_hip_angle_deg": detection["left_hip_angle_deg"],
                "left_ankle_angle_deg": detection["left_ankle_angle_deg"],
                "right_knee_angle_deg": right_knee,
                "right_hip_angle_deg": detection["right_hip_angle_deg"],
                "right_ankle_angle_deg": detection["right_ankle_angle_deg"],
                "confidence": detection["confidence"],
            }
        )

    _emit_progress("complete", total=len(detections), usable=len(samples), dropped=dropped_frames)

    warnings = []
    if not samples:
        warnings.append("No usable MotionAGFormer-L 3D angle frames were produced.")
    else:
        low_ratio = low_confidence_frames / float(max(1, len(detections)))
        if low_ratio > 0.35:
            warnings.append(
                "MotionAGFormer-L received low-confidence 2D detections on many frames. Improve lighting, keep the rider fully visible, and reduce blur."
            )
        if dropped_frames > len(samples):
            warnings.append(
                "Many frames were skipped before MotionAGFormer-L lifting. A stable full-body side view generally works best."
            )

    return {
        "backend": "motionagformer_l_mediapipe",
        "samples": samples,
        "warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True)
    parser.add_argument("--max-samples", type=int, default=180)
    args = parser.parse_args()

    try:
        with contextlib.redirect_stdout(sys.stderr):
            payload = run(args.video, args.max_samples)
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:  # pragma: no cover - runtime dependency
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
