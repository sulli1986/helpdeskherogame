#!/usr/bin/env python3
"""Make the site root always load the newest build.
Usage: version_check.py BUILD_DIR VERSION

Writes BUILD_DIR/version.txt and adds a tiny script to BUILD_DIR/index.html that, on load, fetches
version.txt (bypassing caches). If it names a newer build than this page, the page reloads itself as
index.html?v=<new>, a URL the browser has never cached. Phones otherwise kept showing yesterday's day
from a cached index.html. Archived days have their own version.txt, so they never redirect.
"""
import sys
from pathlib import Path

SCRIPT = """<script>(function(){var v='%s';
fetch('version.txt?t='+Date.now(),{cache:'no-store'}).then(function(r){return r.ok?r.text():'';}).then(function(t){
t=t.trim();if(/^[0-9a-f]{7,40}$/.test(t)&&t!==v&&location.search.indexOf('v='+t)<0){location.replace(location.pathname+'?v='+t);}
}).catch(function(){});})();</script>
"""

if __name__ == "__main__":
    d, v = Path(sys.argv[1]), sys.argv[2].strip()
    page = d / "index.html"
    s = page.read_text()
    if "</head>" not in s:
        sys.exit("version_check: no </head> in %s" % page)
    page.write_text(s.replace("</head>", SCRIPT % v + "</head>", 1))
    (d / "version.txt").write_text(v + "\n")
    print("version_check: build %s" % v)
