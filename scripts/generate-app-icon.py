#!/usr/bin/env python3
import math
from pathlib import Path

SIZE = 1024
OUT = Path('Sources/FricuApp/Resources/AppIcon-master.ppm')
OUT.parent.mkdir(parents=True, exist_ok=True)


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


def mix(a, b, t):
    return tuple(clamp(a[i] * (1 - t) + b[i] * t) for i in range(3))


bg1 = (31, 78, 255)   # blue
bg2 = (104, 33, 214)  # purple
accent = (0, 228, 255)
white = (246, 250, 255)

cx, cy = SIZE / 2, SIZE / 2
r = SIZE * 0.44

buf = bytearray()
for y in range(SIZE):
    for x in range(SIZE):
        dx = (x - cx) / SIZE
        dy = (y - cy) / SIZE
        d = math.sqrt(dx * dx + dy * dy)

        t = min(1.0, max(0.0, (x / SIZE) * 0.55 + (y / SIZE) * 0.45))
        c = list(mix(bg1, bg2, t))

        # soft radial glow
        g = max(0.0, 1.0 - d * 2.2)
        c = [clamp(c[i] + accent[i] * 0.18 * g) for i in range(3)]

        # rounded-square mask fade near corners
        nx = abs((x - cx) / (SIZE * 0.5))
        ny = abs((y - cy) / (SIZE * 0.5))
        corner = max(nx, ny)
        if corner > 0.92:
            fade = min(1.0, (corner - 0.92) / 0.08)
            c = [clamp(c[i] * (1.0 - fade) + 18 * fade) for i in range(3)]

        # cyclist wheels
        lwx, rwx, wy = SIZE * 0.33, SIZE * 0.67, SIZE * 0.67
        wr = SIZE * 0.145
        dl = abs(math.sqrt((x - lwx) ** 2 + (y - wy) ** 2) - wr)
        dr = abs(math.sqrt((x - rwx) ** 2 + (y - wy) ** 2) - wr)
        if dl < 4.0 or dr < 4.0:
            c = [clamp(white[i] * 0.95) for i in range(3)]

        # bike frame strokes (distance to line segments)
        def dist_to_seg(px, py, ax, ay, bx, by):
            abx, aby = bx - ax, by - ay
            apx, apy = px - ax, py - ay
            denom = abx * abx + aby * aby
            if denom == 0:
                return math.hypot(px - ax, py - ay)
            t = max(0.0, min(1.0, (apx * abx + apy * aby) / denom))
            qx, qy = ax + t * abx, ay + t * aby
            return math.hypot(px - qx, py - qy)

        lines = [
            (SIZE * 0.33, SIZE * 0.67, SIZE * 0.49, SIZE * 0.47),
            (SIZE * 0.49, SIZE * 0.47, SIZE * 0.57, SIZE * 0.67),
            (SIZE * 0.33, SIZE * 0.67, SIZE * 0.57, SIZE * 0.67),
            (SIZE * 0.49, SIZE * 0.47, SIZE * 0.67, SIZE * 0.67),
            (SIZE * 0.49, SIZE * 0.47, SIZE * 0.56, SIZE * 0.40),
        ]
        for ax, ay, bx, by in lines:
            if dist_to_seg(x, y, ax, ay, bx, by) < 3.5:
                c = [clamp(white[i]) for i in range(3)]

        # rider head
        if math.hypot(x - SIZE * 0.53, y - SIZE * 0.30) < SIZE * 0.032:
            c = [clamp(white[i]) for i in range(3)]

        # rider body/arm
        body = [
            (SIZE * 0.53, SIZE * 0.34, SIZE * 0.49, SIZE * 0.47),
            (SIZE * 0.53, SIZE * 0.36, SIZE * 0.61, SIZE * 0.40),
        ]
        for ax, ay, bx, by in body:
            if dist_to_seg(x, y, ax, ay, bx, by) < 4.0:
                c = [clamp(white[i]) for i in range(3)]

        # subtle pulse ring for "training" feeling
        ring = abs(math.sqrt((x - cx) ** 2 + (y - cy) ** 2) - r)
        if ring < 2.0:
            c = [clamp(c[i] * 0.8 + accent[i] * 0.35) for i in range(3)]

        buf.extend(bytes(c))

with OUT.open('wb') as f:
    f.write(f'P6\n{SIZE} {SIZE}\n255\n'.encode('ascii'))
    f.write(buf)

print(OUT)
