#!/usr/bin/env bash
# Render the daily promo clip: a ~30s 1080x1920 Short with voiceover, captions and an original
# synthesized backing track, plus caption.txt for posting. Needs ffmpeg, python3-numpy, python3-pil;
# the voice uses Piper (pip install piper-tts), and the clip still renders without it.
# Usage: GODOT=/path/to/godot GAME_URL=https://... tools/make_clip.sh [out_dir]
set -euo pipefail
GODOT="${GODOT:-godot}"
OUT="${1:-build/clip}"
mkdir -p "$OUT"

python3 tools/clip_text.py "$OUT" "${GAME_URL:-}"
python3 -c "import piper" 2>/dev/null || pip install -q --user "piper-tts>=1.3,<2" 2>/dev/null \
  || pip install -q --user --break-system-packages "piper-tts>=1.3,<2" || echo "::warning::piper-tts not installed"
python3 tools/clip_voice.py "$OUT"
python3 tools/make_music.py "$OUT/music.wav" 40 "$(cat "$OUT/day.txt")"

# Render at 720x1280 (portrait) with fixed 30fps so the clip is smooth regardless of machine speed.
xvfb-run -a -s "-screen 0 800x1400x24" \
  "$GODOT" --path . --rendering-driver opengl3 --resolution 720x1280 \
  --write-movie "$OUT/raw.avi" --fixed-fps 30 -- --demo

FONT="$(fc-match -f '%{file}' 'DejaVu Sans:bold' 2>/dev/null || true)"
[ -f "$FONT" ] || FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

python3 tools/clip_compose.py "$OUT" "$FONT"

rm -f "$OUT/raw.avi" "$OUT/music.wav" "$OUT/voice.wav" "$OUT/outro.wav" "$OUT"/ov_*.png
ls -la "$OUT"
