#!/usr/bin/env python3
"""Print "N <sha>" for each Day: the LAST commit on main whose CHANGELOG top heading is Day N.
That includes same-day fixes. Needs full history (actions/checkout fetch-depth: 0).
"""
import re
import subprocess

shas = subprocess.run(["git", "rev-list", "--reverse", "HEAD"], capture_output=True, text=True, check=True).stdout.split()
last = {}
for sha in shas:
    r = subprocess.run(["git", "show", f"{sha}:CHANGELOG.md"], capture_output=True, text=True)
    m = re.search(r"^## Day (\d+)", r.stdout, re.M) if r.returncode == 0 else None
    if m:
        last[int(m.group(1))] = sha
for n in sorted(last):
    print(n, last[n])
