#!/usr/bin/env python3
"""Add analytics tags to a Godot export preset's head_include.
Usage: inject_analytics.py PATH/TO/export_presets.cfg

Env (both optional; each tag is added only if set and valid):
  UMAMI_WEBSITE_ID    Umami website ID
  GA_MEASUREMENT_ID   Google Analytics 4 measurement ID (G-XXXXXXXXXX, not the numeric property ID)
"""
import os
import re
import sys
from pathlib import Path


def tags() -> str:
    out = []
    uid = os.environ.get("UMAMI_WEBSITE_ID", "").strip()
    if uid:
        out.append('<script defer src="https://cloud.umami.is/script.js" data-website-id="%s"></script>' % uid)
    ga = os.environ.get("GA_MEASUREMENT_ID", "").strip()
    if ga and re.fullmatch(r"G-[A-Z0-9]{4,16}", ga):
        out.append(
            '<script async src="https://www.googletagmanager.com/gtag/js?id=%s"></script>'
            "<script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}"
            "gtag('js',new Date());gtag('config','%s');</script>" % (ga, ga))
    elif ga:
        print("GA: '%s' isn't a measurement ID (G-XXXXXXXXXX); skipped" % ga, file=sys.stderr)
    return "\n".join(out)


if __name__ == "__main__":
    p = Path(sys.argv[1])
    s = p.read_text()
    add = tags()
    if not add or "googletagmanager" in s or "umami.is" in s:
        print("analytics: nothing to add")
        sys.exit(0)
    esc = add.replace("\\", "\\\\").replace('"', '\\"')
    s = s.replace('</script>"', "</script>\n" + esc + '"', 1)
    p.write_text(s)
    print("analytics: injected")
