#!/usr/bin/env python3
"""Turn the raw portrait gameplay capture into the finished daily clip (a ~30s Short).

Usage: clip_compose.py OUT_DIR FONT_FILE
Reads OUT_DIR/raw.avi (gameplay + game sounds), music.wav (make_music.py), voice.wav, outro.wav and
voice.json (clip_voice.py), hook.txt / host.txt / day.txt (clip_text.py). Writes OUT_DIR/clip.mp4.

Built to stop the scroll and send people to the game:
  frame 0      hook card ("NEW TODAY" + the day's headline) is fully on screen: it's the thumbnail
  0s+          voiceover starts at once; big word-by-word captions follow it (most watch muted)
  always       "DAY N" pill at the top, thin progress bar, music ducked under the voice
  end          call to action: PLAY FREE, the URL, "link below", spoken outro
"""
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

out, font_path = Path(sys.argv[1]), sys.argv[2]
W, H = 1080, 1920
YELLOW = (255, 213, 74, 255)
INK = (20, 22, 30, 255)
WHITE = (255, 255, 255, 255)

day = int((out / "day.txt").read_text().strip() or 0)
hook = (out / "hook.txt").read_text(encoding="utf-8").strip()
host = (out / "host.txt").read_text(encoding="utf-8").strip()
voice = json.loads((out / "voice.json").read_text(encoding="utf-8"))
dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                            str(out / "raw.avi")], capture_output=True, text=True, check=True).stdout.strip())
end_at = max(0.0, dur - max(4.2, voice["outro"]["length"] + 1.0))
hook_end = min(end_at, max(2.8, voice["lines"][0]["end"] + 0.4 if voice["lines"] else 3.0))


def font(size):
    return ImageFont.truetype(font_path, size)


def wrap(draw, text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=f) <= width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def pill(draw, cx, top, text, f, fill, ink, pad_x=34, pad_y=16):
    tw = draw.textlength(text, font=f)
    asc, desc = f.getmetrics()
    h = asc + desc + 2 * pad_y
    draw.rounded_rectangle((cx - tw / 2 - pad_x, top, cx + tw / 2 + pad_x, top + h), radius=h / 2, fill=fill)
    draw.text((cx, top + pad_y + asc), text, font=f, fill=ink, anchor="ms")
    return top + h


def shadowed(draw, xy, text, f, fill, anchor="ms"):
    x, y = xy
    draw.text((x + 3, y + 4), text, font=f, fill=(0, 0, 0, 170), anchor=anchor)
    draw.text((x, y), text, font=f, fill=fill, anchor=anchor)


def save(img, name):
    p = out / name
    img.save(p)
    return p


# Header: soft top gradient + DAY pill + the series line
img = Image.new("RGBA", (W, 330), (0, 0, 0, 0))
grad = Image.new("L", (1, 330))
for y in range(330):
    grad.putpixel((0, y), int(150 * (1 - y / 330) ** 1.4))
img.paste(Image.new("RGBA", (W, 330), (0, 0, 0, 255)), (0, 0), grad.resize((W, 330)))
d = ImageDraw.Draw(img)
bottom = pill(d, W / 2, 60, f"DAY {day}", font(66), YELLOW, INK)
shadowed(d, (W / 2, bottom + 62), "An AI adds a feature to this game every day", font(36), WHITE)
header = save(img, "ov_header.png")

# Hook card: on screen from frame 0 (the thumbnail) until the first spoken line is done
img = Image.new("RGBA", (W, 640), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
f = font(74)
width = 900
lines = wrap(d, hook, f, width)[:3]
while width > 300 and len(wrap(d, hook, f, width - 20)) == len(lines):  # balance the lines
    width -= 20
lines = wrap(d, hook, f, width)[:3]
step = 92
card_h = 130 + step * len(lines) + 40
d.rounded_rectangle((50, 30, W - 50, 30 + card_h), radius=44, fill=(255, 255, 255, 246))
pill(d, W / 2, 62, "NEW TODAY", font(36), YELLOW, INK, pad_x=26, pad_y=10)
for k, line in enumerate(lines):
    d.text((W / 2, 30 + 130 + 66 + k * step), line, font=f, fill=INK, anchor="ms")
hook_png = save(img, "ov_hook.png")


# Captions: the voiceover two or three words at a time, big, in the lower third
def caption_png(text, k):
    img = Image.new("RGBA", (W, 200), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(84)
    while d.textlength(text, font=f) > W - 80 and f.size > 44:
        f = font(f.size - 4)
    d.text((W / 2, 130), text, font=f, fill=WHITE, anchor="ms", stroke_width=10, stroke_fill=(0, 0, 0, 255))
    return save(img, f"ov_cap_{k}.png")


caps = []
for ln in voice["lines"]:
    if ln["start"] >= end_at:
        break
    words = ln["text"].split()
    chunks, cur = [], []
    for w in words:
        cur.append(w)
        if len(cur) == 3 or w[-1] in ".,?!":
            chunks.append(" ".join(cur))
            cur = []
    if cur:
        chunks.append(" ".join(cur))
    total = sum(len(c) + 2 for c in chunks)
    t = ln["start"]
    span = min(ln["end"], end_at) - ln["start"]
    for c in chunks:
        dt = span * (len(c) + 2) / total
        caps.append((caption_png(c.upper().rstrip(".,"), len(caps)), t, t + dt))
        t += dt

# End card: the reason to tap through
img = Image.new("RGBA", (W, H), (8, 10, 18, 205))
d = ImageDraw.Draw(img)
y = 640
shadowed(d, (W / 2, y), "PLAY IT FREE", font(124), YELLOW)
shadowed(d, (W / 2, y + 96), "in your browser · no download", font(48), WHITE)
if host:
    f = font(58)
    while d.textlength(host, font=f) > W - 200:
        f = font(f.size - 4)
    tw = d.textlength(host, font=f)
    d.rounded_rectangle((W / 2 - tw / 2 - 44, y + 180, W / 2 + tw / 2 + 44, y + 290), radius=55, fill=WHITE)
    d.text((W / 2, y + 257), host, font=f, fill=INK, anchor="ms")
shadowed(d, (W / 2, y + 400), "Link in the description", font(56), WHITE)
shadowed(d, (W / 2, y + 520), f"Follow for Day {day + 1} tomorrow", font(52), (220, 224, 235, 255))
end_png = save(img, "ov_end.png")

# ---------------------------------------------------------------- ffmpeg
inputs = ["-i", str(out / "raw.avi"), "-i", str(out / "music.wav"), "-i", str(out / "voice.wav"),
          "-i", str(out / "outro.wav")]
chain = ["[0:v]scale=1080:1920:flags=lanczos,setsar=1[v0]"]
cur = "v0"
idx = 4


def overlay(png, start, end, y, fade=0.2):
    global cur, idx
    inputs.extend(["-loop", "1", "-t", f"{end:.2f}", "-i", str(png)])
    fx = "format=rgba"
    if fade:
        if start > 0:
            fx += f",fade=t=in:st={start:.2f}:d={fade}:alpha=1"
        fx += f",fade=t=out:st={max(start + fade, end - fade):.2f}:d={fade}:alpha=1"
    chain.append(f"[{idx}:v]{fx}[o{idx}]")
    chain.append(f"[{cur}][o{idx}]overlay=0:{y}:enable='between(t,{start:.2f},{end:.2f})'[v{idx}]")
    cur = f"v{idx}"
    idx += 1


overlay(header, 0, end_at + 0.2, 0)
overlay(hook_png, 0, hook_end, 520)
for png, s, e in caps:
    overlay(png, s, e, 1380, fade=0)
overlay(end_png, end_at, dur, 0, fade=0.25)
chain.append(f"color=c=0xFFD54A:s={W}x12:d={dur:.2f}[bar]")
chain.append(f"[{cur}][bar]overlay=x='-w+W*t/{dur:.2f}':y=0:shortest=1[vout]")

# Audio: voice on top, music ducked under it (sidechain), game sounds (chimes, buzzes) underneath.
fmt = "aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo"
ms = int(end_at * 1000 + 250)
chain += [
    f"[2:a]{fmt},apad[vl]",
    f"[3:a]{fmt},adelay={ms}|{ms},apad[vo]",
    f"[vl][vo]amix=inputs=2:normalize=0,atrim=0:{dur:.2f},volume=1.5,asplit=2[vkey][vmix]",
    f"[1:a]{fmt},atrim=0:{dur:.2f},volume=0.6[mus]",
    "[mus][vkey]sidechaincompress=threshold=0.015:ratio=9:attack=15:release=400[duck]",
    f"[0:a]{fmt},volume=0.45[game]",
    f"[duck][vmix][game]amix=inputs=3:normalize=0:duration=first,alimiter=limit=0.95,"
    f"afade=t=out:st={dur - 1.2:.2f}:d=1.2[aout]",
]
cmd = ["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(chain),
       "-map", "[vout]", "-map", "[aout]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
       "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart",
       "-t", f"{dur:.2f}", str(out / "clip.mp4")]
subprocess.run(cmd, check=True)
print(f"clip.mp4: {dur:.1f}s, {len(caps)} captions, voice {'on' if voice['spoken'] else 'off'}, end card at {end_at:.1f}s")
