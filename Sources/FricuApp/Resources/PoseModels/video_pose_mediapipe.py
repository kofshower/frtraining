#!/usr/bin/env python3
import argparse
import json
import math
import sys


def _load_dependencies():
    try:
        import cv2  # type: ignore
        import mediapipe as mp  # type: ignore
        return cv2, mp
    except Exception as exc:  # pragma: no cover - runtime dependency
        raise RuntimeError(f"Missing dependency: {exc}") from exc


def _joint_from_landmark(landmark):
    return {
        "x": float(landmark.x),
        "y": float(landmark.y),
        "confidence": float(getattr(landmark, "visibility", 0.0)),
    }


def _angle_3d(a, b, c):
    bax = a.x - b.x
    bay = a.y - b.y
    baz = a.z - b.z
    bcx = c.x - b.x
    bcy = c.y - b.y
    bcz = c.z - b.z
    dot = bax * bcx + bay * bcy + baz * bcz
    mag_ba = math.sqrt(bax * bax + bay * bay + baz * baz)
    mag_bc = math.sqrt(bcx * bcx + bcy * bcy + bcz * bcz)
    if mag_ba < 1e-8 or mag_bc < 1e-8:
        return None
    cosine = max(-1.0, min(1.0, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cosine))


def run(video_path: str, max_samples: int):
    cv2, mp = _load_dependencies()

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError("Unable to open video file.")

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    if fps <= 0:
        fps = 30.0
    if total_frames <= 0:
        total_frames = max(1, int(cap.get(cv2.CAP_PROP_POS_FRAMES) or 1))

    target_count = max(24, min(int(max_samples), max(1, total_frames)))
    if total_frames <= 1:
        frame_indices = [0]
    else:
        import numpy as np  # type: ignore
        frame_indices = np.linspace(0, total_frames - 1, num=target_count, dtype=int).tolist()

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
        "left_shoulder": mp_pose.PoseLandmark.LEFT_SHOULDER.value,
        "right_shoulder": mp_pose.PoseLandmark.RIGHT_SHOULDER.value,
        "left_hip": mp_pose.PoseLandmark.LEFT_HIP.value,
        "right_hip": mp_pose.PoseLandmark.RIGHT_HIP.value,
        "left_knee": mp_pose.PoseLandmark.LEFT_KNEE.value,
        "right_knee": mp_pose.PoseLandmark.RIGHT_KNEE.value,
        "left_ankle": mp_pose.PoseLandmark.LEFT_ANKLE.value,
        "right_ankle": mp_pose.PoseLandmark.RIGHT_ANKLE.value,
        "left_foot_index": mp_pose.PoseLandmark.LEFT_FOOT_INDEX.value,
        "right_foot_index": mp_pose.PoseLandmark.RIGHT_FOOT_INDEX.value,
    }

    samples = []
    low_confidence_frames = 0

    for output_index, frame_index in enumerate(frame_indices):
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()
        if not ok or frame is None:
            continue
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = pose.process(frame_rgb)
        if not result.pose_landmarks:
            continue

        landmarks = result.pose_landmarks.landmark
        joints = {}
        confidence_values = []
        for key, idx in lm_idx.items():
            if idx < 0 or idx >= len(landmarks):
                continue
            joint = _joint_from_landmark(landmarks[idx])
            joints[key] = joint
            confidence_values.append(joint["confidence"])

        if len(joints) < 8:
            continue
        mean_confidence = sum(confidence_values) / max(1, len(confidence_values))
        if mean_confidence < 0.45:
            low_confidence_frames += 1

        left_knee_angle_deg = None
        left_hip_angle_deg = None
        right_knee_angle_deg = None
        right_hip_angle_deg = None
        if result.pose_world_landmarks:
            world = result.pose_world_landmarks.landmark
            try:
                left_knee_angle_deg = _angle_3d(
                    world[lm_idx["left_hip"]],
                    world[lm_idx["left_knee"]],
                    world[lm_idx["left_ankle"]],
                )
                left_hip_angle_deg = _angle_3d(
                    world[lm_idx["left_shoulder"]],
                    world[lm_idx["left_hip"]],
                    world[lm_idx["left_knee"]],
                )
                right_knee_angle_deg = _angle_3d(
                    world[lm_idx["right_hip"]],
                    world[lm_idx["right_knee"]],
                    world[lm_idx["right_ankle"]],
                )
                right_hip_angle_deg = _angle_3d(
                    world[lm_idx["right_shoulder"]],
                    world[lm_idx["right_hip"]],
                    world[lm_idx["right_knee"]],
                )
            except Exception:
                left_knee_angle_deg = None
                left_hip_angle_deg = None
                right_knee_angle_deg = None
                right_hip_angle_deg = None

        samples.append(
            {
                "id": int(output_index),
                "time_seconds": float(frame_index / fps),
                "joints": joints,
                "left_knee_angle_deg": left_knee_angle_deg,
                "left_hip_angle_deg": left_hip_angle_deg,
                "right_knee_angle_deg": right_knee_angle_deg,
                "right_hip_angle_deg": right_hip_angle_deg,
            }
        )

    cap.release()
    pose.close()

    warnings = []
    if not samples:
        warnings.append("No body pose frame returned by MediaPipe.")
    else:
        low_ratio = low_confidence_frames / float(len(samples))
        if low_ratio > 0.35:
            warnings.append(
                "Low keypoint confidence on many frames. Improve lighting or add visible markers on hip/knee/ankle."
            )

        toe_frames = 0
        for sample in samples:
            joints = sample.get("joints", {})
            if "left_foot_index" in joints and "right_foot_index" in joints:
                toe_frames += 1
        toe_ratio = toe_frames / float(len(samples))
        if toe_ratio < 0.6:
            warnings.append("Toe landmarks are unstable; place high-contrast markers on shoe tips.")

    return {
        "backend": "mediapipe_blazepose_ghum",
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
