#!/usr/bin/env python3
"""Add the Umami analytics tag to a Godot export preset if UMAMI_WEBSITE_ID is set.
Usage: inject_umami.py PATH/TO/export_presets.cfg
"""
import os
import sys
from pathlib import Path

uid = os.environ.get("UMAMI_WEBSITE_ID", "").strip()
p = Path(sys.argv[1])
s = p.read_text()
if not uid or "umami" in s:
    print("Umami: skipped" if not uid else "Umami: already present")
    sys.exit(0)
tag = '<script defer src=\\"https://cloud.umami.is/script.js\\" data-website-id=\\"%s\\"></script>' % uid
s = s.replace("</script>\"", "</script>\n" + tag + "\"", 1)
p.write_text(s)
print("Umami: injected")
