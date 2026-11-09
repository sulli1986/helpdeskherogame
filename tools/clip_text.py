#!/usr/bin/env python3
"""Build overlay text + social caption from the top CHANGELOG entry.

Usage: clip_text.py OUT_DIR [GAME_URL]
Writes: day.txt, title.txt, sub.txt, footer.txt, caption.txt
"""
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

(out / "day.txt").write_text(num)
(out / "title.txt").write_text(f"{day} of an AI\nbuilding an IT game")
(out / "sub.txt").write_text("\n".join(textwrap.wrap(hook, 26)[:3]))
host = url.split("://", 1)[-1] if url else ""
(out / "footer.txt").write_text(f"Play free in your browser\n{host}" if host else "Play free in your browser")

caption = [
    f"{day}: an AI makes one change to this IT helpdesk game every single day.",
    "",
    *[f"• {b}" for b in bullets],
    "",
    f"Play free (no download): {url}" if url else "Play free in your browser, link in bio.",
    "",
    "#gamedev #ITsupport #MSP #helpdesk #godot #ai #buildinpublic",
]
(out / "caption.txt").write_text("\n".join(caption) + "\n")
print(f"{day} | {hook}")
