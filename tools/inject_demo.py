#!/usr/bin/env python3
"""Make an older checkout able to render the promo clip.

Usage: inject_demo.py OLD_CHECKOUT_DIR CURRENT_REPO_DIR
Every Helpdesk Hero day has had demo mode since Day 1, so an old day keeps its own demo.gd
(it matches that day's code). Only copies the current one in if it's missing.
"""
import shutil
import sys
from pathlib import Path

old, cur = Path(sys.argv[1]), Path(sys.argv[2])
dst = old / "scripts/demo.gd"
if not dst.exists():
    shutil.copy(cur / "scripts/demo.gd", dst)
    print("copied demo.gd into", old)
