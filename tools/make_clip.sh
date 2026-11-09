#!/usr/bin/env bash
# Render the daily promo clip: 1080x1920 MP4 with captions + caption.txt for posting.
# Usage: GODOT=/path/to/godot GAME_URL=https://... tools/make_clip.sh [out_dir]
set -euo pipefail
GODOT="${GODOT:-godot}"
OUT="${1:-build/clip}"
mkdir -p "$OUT"

python3 tools/clip_text.py "$OUT" "${GAME_URL:-}"
printf 'Follow for\nDay %s tomorrow' "$(( $(cat "$OUT/day.txt") + 1 ))" > "$OUT/cta.txt"

# Render at 720x1280 (portrait) with fixed 30fps so the clip is smooth regardless of machine speed.
xvfb-run -a -s "-screen 0 800x1400x24" \
  "$GODOT" --path . --rendering-driver opengl3 --resolution 720x1280 \
  --write-movie "$OUT/raw.avi" --fixed-fps 30 -- --demo

FONT="$(fc-match -f '%{file}' 'DejaVu Sans:bold' 2>/dev/null || true)"
[ -f "$FONT" ] || FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

# One drawtext per line: newer ffmpeg renders "\n" inside a textfile as a missing-glyph box.
VF="$(python3 tools/clip_filter.py "$OUT" "$FONT")"
ffmpeg -y -loglevel error -i "$OUT/raw.avi" -vf "$VF" \
  -c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p -movflags +faststart -an "$OUT/clip.mp4"

rm -f "$OUT/raw.avi"
ls -la "$OUT"
