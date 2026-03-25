# Bike Keypoint Self-Training

This pipeline trains a compact keypoint model for three road-bike landmarks:

1. `bb_center`
2. `crank_end`
3. `pedal_center`

It is intentionally **self-supervised / pseudo-labeled**, not fully unsupervised. In practice, semantic keypoints like BB and pedal are too specific to expect stable discovery without any structure. The pipeline therefore uses the existing human pose stack to bootstrap labels and adds a flip-consistency loss during training.

## Why This Exists

The current fitting flow estimates the crank circle from rider joints and toe/ankle trajectories. That works surprisingly well, but it is still a geometry-only fallback. This training path gives us a way to build a bike-specific detector that can later replace or refine the current heuristic.

## Real-Video Workflow

Generate pseudo labels from side-view riding videos:

```bash
python scripts/bike_keypoint_selftrain.py pseudo-label \
  ~/Downloads/FricuImportedVideos \
  --output-dir /tmp/bike-keypoints-real
```

Train the heatmap model:

```bash
python scripts/bike_keypoint_selftrain.py train \
  --dataset /tmp/bike-keypoints-real/dataset.json \
  --output-dir /tmp/bike-keypoints-run \
  --epochs 8
```

Evaluate the checkpoint:

```bash
python scripts/bike_keypoint_selftrain.py evaluate \
  --dataset /tmp/bike-keypoints-real/dataset.json \
  --checkpoint /tmp/bike-keypoints-run/best.pt
```

Run inference on a video:

```bash
python scripts/bike_keypoint_selftrain.py infer-video \
  --video ~/Downloads/FricuImportedVideos/side.mov \
  --checkpoint /tmp/bike-keypoints-run/best.pt \
  --output /tmp/bike-keypoints-prediction.json
```

## Synthetic Smoke Test

Release verification runs a tiny synthetic smoke test:

```bash
bash scripts/test-bike-keypoint-selftrain.sh
```

This verifies that:

- the training script can generate a dataset
- a checkpoint can be trained end-to-end
- evaluation returns finite metrics

It is not meant to prove real-world accuracy. It is only a guardrail against broken training code.

## Pseudo Label Semantics

The pseudo labels are derived as follows:

- `pedal_center`: a forefoot proxy interpolated along the ankle-to-toe vector
- `bb_center`: robust circle fit center over the pedal trajectory
- `crank_end`: projection of the pedal proxy onto the fitted crank circle

So the semantics are stable enough for model training, but still approximate. If you later want production-grade accuracy, the next upgrade is to add a small manually reviewed calibration set and fine-tune the model on it.
