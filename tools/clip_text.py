#!/usr/bin/env python3
"""Build overlay text + social caption from the top CHANGELOG entry.

Usage: clip_text.py OUT_DIR [GAME_URL]
Writes: day.txt, hook.txt, host.txt, sub.txt, caption.txt, narration.json
Narration (the voiceover) comes from tools/clip_script.json when its "day" is today's, otherwise
it's made from the CHANGELOG bullets.
"""
import json
import re
import sys
import textwrap
from pathlib import Path

out = Path(sys.argv[1])
url = (sys.argv[2] if len(sys.argv) > 2 else "").strip().rstrip("/")
if url and not url.startswith("http"):
    url = "https://" + url
out.mkdir(parents=True, exist_ok=True)

md = Path("CHANGELOG.md").read_text(encoding="utf-8")
m = re.search(r"^## (.+?)\n(.*?)(?=^## |\Z)", md, re.S | re.M)
heading = m.group(1).strip() if m else "Day ?"
bullets = [l[2:].strip() for l in (m.group(2) if m else "").splitlines() if l.startswith("- ")]
day = heading.split("—")[0].strip()                       # "Day 2"
num = re.sub(r"\D", "", day) or "0"
first = bullets[0] if bullets else "A new update"
# Short hook: text before a colon reads best on a phone ("New minimap in the bottom-right corner")
hook = first.split(":")[0].strip()

host = url.split("://", 1)[-1] if url else ""
(out / "day.txt").write_text(num)
(out / "hook.txt").write_text(hook, encoding="utf-8")
(out / "host.txt").write_text(host, encoding="utf-8")
(out / "sub.txt").write_text("\n".join(textwrap.wrap(hook, 26)[:3]))  # post_clip.sh builds the title from it


def sentences(text):
    text = re.sub(r"\s*\([^)]*\)", "", text)  # drop "(or tap ...)" asides: they read badly aloud
    return [x.strip() for x in re.split(r"(?<=[.!?])\s+|\.\s*$", text) if x.strip()]


def say(text, n=22):
    """One spoken line: "Label: rest" becomes "Label. Rest", long ones stop at a comma before n words."""
    text = re.sub(r"^([^:]{1,30}):\s*(\w)", lambda m: f"{m.group(1)}. {m.group(2).upper()}", text)
    w = text.split()
    if len(w) > n:
        cut = " ".join(w[:n])
        text = cut[:cut.rfind(",")] if "," in cut else cut
    text = text.strip().rstrip(",;:.")
    return text[:1].upper() + text[1:] + "."


script = Path(__file__).resolve().parent / "clip_script.json"
lines = []
if script.exists():
    js = json.loads(script.read_text(encoding="utf-8"))
    if str(js.get("day")) == num:
        lines = [l if isinstance(l, dict) else {"text": l} for l in js.get("lines", [])]
if not lines:  # no script for today: speak the hook, then the first sentence of each bullet
    lines.append({"text": hook.rstrip(".!") + "!"})
    rest = first.split(":", 1)[1] if ":" in first else ""
    for chunk in [rest] + bullets[1:3]:
        ss = sentences(chunk)
        if ss:
            lines.append({"text": say(ss[0])})
narration = {"lines": lines[:5], "outro": "An A.I. adds something new every day. Play it free, link in the description."}
(out / "narration.json").write_text(json.dumps(narration, indent=1), encoding="utf-8")

caption = [
    f"▶ Play free in your browser, no download: {url}" if url else "▶ Play free in your browser, link in bio.",
    "",
    f"{day}: {hook}. An AI makes one change to this IT helpdesk game every single day.",
    "",
    *[f"• {b}" for b in bullets],
    "",
    "Follow to see what it builds tomorrow.",
    "",
    "#gamedev #ITsupport #MSP #helpdesk #godot #ai #buildinpublic",
]
(out / "caption.txt").write_text("\n".join(caption) + "\n")
print(f"{day} | {hook}")
