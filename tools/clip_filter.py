#!/usr/bin/env python3
"""Build the ffmpeg -vf chain for the clip overlays, one drawtext per text line.

Usage: clip_filter.py OUT_DIR FONT_FILE   (prints the filter string)
"""
import sys
from pathlib import Path

out, font = Path(sys.argv[1]), sys.argv[2]
H = 1920
box = "box=1:boxcolor=black@0.55:boxborderw=20"
parts = ["scale=1080:1920:flags=lanczos"]


def block(name, size, color, top, enable=None, center_v=False):
    lines = [l for l in (out / f"{name}.txt").read_text(encoding="utf-8").splitlines() if l.strip()]
    step = int(size * 1.45)
    if center_v:
        top = (H - step * len(lines)) // 2
    for k, line in enumerate(lines):
        f = out / f"{name}_{k}.txt"
        f.write_text(line.strip(), encoding="utf-8")
        d = (f"drawtext=fontfile={font}:textfile={f}:fontsize={size}:fontcolor={color}:{box}"
             f":x=(w-tw)/2:y={top + k * step}")
        if enable:
            d += f":enable='{enable}'"
        parts.append(d)


block("title", 76, "white", 170)
block("sub", 56, "0xFFD54A", 450, enable="lt(t,6)")
block("footer", 46, "white", H - 470 - 2 * int(46 * 1.45))
block("cta", 84, "0xFFD54A", 0, enable="gte(t,53)", center_v=True)
print(",".join(parts))
