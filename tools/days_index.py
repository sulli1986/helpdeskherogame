#!/usr/bin/env python3
"""Generate /days/index.html: every day's build, what changed, and its clip.
Usage: days_index.py OUT_FILE
"""
import html
import os
import re
import sys
from pathlib import Path

md = Path("CHANGELOG.md").read_text(encoding="utf-8")
entries = re.findall(r"^## Day (\d+)\s*[—-]\s*(\S+)\n(.*?)(?=^## |\Z)", md, re.S | re.M)
latest = max((int(n) for n, _, _ in entries), default=0)

cards = []
for n, date, body in entries:
    bullets = "".join(f"<li>{html.escape(l[2:].strip())}</li>" for l in body.splitlines() if l.startswith("- "))
    tag = '<span class="tag">Latest</span>' if int(n) == latest else ""
    play = "/" if int(n) == latest else f"/days/day-{n}/index.html"
    cards.append(f"""
  <article>
    <header><h2>Day {n} {tag}</h2><time>{html.escape(date)}</time></header>
    <ul>{bullets}</ul>
    <p class="actions"><a class="btn" href="{play}">Play Day {n}</a>
    <a href="/clips/day-{n}.mp4">Watch clip</a></p>
  </article>""")

uid = os.environ.get("UMAMI_WEBSITE_ID", "").strip()
umami = f'<script defer src="https://cloud.umami.is/script.js" data-website-id="{html.escape(uid)}"></script>' if uid else ""
page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Every day so far · Helpdesk Hero</title>
{umami}
<style>
:root{{color-scheme:dark}}
body{{margin:0;font:16px/1.5 system-ui,sans-serif;background:#0b0f19;color:#e8ecf3}}
main{{max-width:760px;margin:0 auto;padding:32px 18px 64px}}
h1{{font-size:1.9rem;margin:0 0 4px}} .lede{{color:#9aa6b8;margin:0 0 28px}}
article{{background:#141a28;border:1px solid #232c3f;border-radius:12px;padding:18px 20px;margin:0 0 14px}}
article header{{display:flex;justify-content:space-between;align-items:baseline;gap:12px}}
h2{{margin:0;font-size:1.25rem}} time{{color:#8792a6;font-size:.9rem}}
.tag{{background:#ffd54a;color:#111;border-radius:999px;padding:2px 9px;font-size:.75rem;vertical-align:middle;margin-left:6px}}
ul{{margin:10px 0 14px;padding-left:20px;color:#cfd6e2}}
.actions{{display:flex;gap:16px;align-items:center;margin:0}}
a{{color:#7cc4ff}} .btn{{background:#2f6bff;color:#fff;text-decoration:none;padding:8px 16px;border-radius:8px;font-weight:600}}
</style></head><body><main>
<h1>Every day so far</h1>
<p class="lede">An AI makes one change to this game every day. Play any day's version as it was, or <a href="/">jump back to today</a>.
Older days share your account, but they can't overwrite progress made in newer versions.</p>
{''.join(cards)}
</main></body></html>
"""
out = Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(page, encoding="utf-8")
print(f"wrote {out} with {len(entries)} days")
