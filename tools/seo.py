#!/usr/bin/env python3
"""Search and share metadata for the site.
Usage: seo.py WEB_DIR SITE_OUT_DIR [SITE_URL]

- Adds a descriptive title, meta description, canonical link, Open Graph / Twitter cards and
  schema.org VideoGame data to WEB_DIR/index.html, plus a <noscript> summary crawlers can read
  (the game itself is a canvas with no text in the page).
- Writes robots.txt and sitemap.xml to SITE_OUT_DIR (uploaded to the site root).
SITE_URL (the public https://... address, from the GAME_URL variable) is needed for the absolute
URLs; without it only the title, description and noscript text are added.
Keep the copy accurate when the game changes (it's what search results show).
"""
import html
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

TITLE = "Helpdesk Hero: free IT helpdesk simulator game in your browser"
DESC = ("Free IT helpdesk sim you play in the browser. Work an MSP ticket queue against the SLA clock: "
        "phishing, lockouts, outages, MFA attacks. New features every day.")
ABOUT = [
    "Helpdesk Hero is a free IT helpdesk simulator game that runs in your browser, on desktop and phone.",
    "You work a shift at a managed service provider (MSP): tickets arrive in a queue with SLA timers, "
    "and you read the evidence and pick the right fix before the client escalates.",
    "Spot phishing emails from their headers, unlock accounts, sort out share access and printers, "
    "choose Microsoft 365 licences, contain MFA fatigue attacks from the sign-in logs, and diagnose "
    "network outages by typing ipconfig, ping, nslookup and tracert into a simulated command prompt, "
    "then fix the server or router and prove the fix worked.",
    "Fast, correct fixes earn cash and reputation; wrong calls and SLA breaches cost you the client. "
    "Make a free account to save your career and climb the leaderboard.",
    "An AI makes one improvement to the game every day.",
]


def main() -> None:
    web, out = Path(sys.argv[1]), Path(sys.argv[2])
    site = (sys.argv[3] if len(sys.argv) > 3 else "").strip().rstrip("/")
    if site and not re.fullmatch(r"https://[A-Za-z0-9.-]+(:\d+)?", site):
        print("seo: SITE_URL '%s' isn't https://host; skipping absolute URLs" % site, file=sys.stderr)
        site = ""
    e = html.escape
    head = [
        '<meta name="description" content="%s">' % e(DESC),
        '<meta name="theme-color" content="#0b0f19">',
    ]
    if site:
        img = site + "/clips/og.jpg"  # a frame of the latest daily clip (clip job)
        head += [
            '<link rel="canonical" href="%s/">' % site,
            '<meta property="og:type" content="website">',
            '<meta property="og:site_name" content="Helpdesk Hero">',
            '<meta property="og:title" content="%s">' % e(TITLE),
            '<meta property="og:description" content="%s">' % e(DESC),
            '<meta property="og:url" content="%s/">' % site,
            '<meta property="og:image" content="%s">' % img,
            '<meta property="og:image:width" content="1200">',
            '<meta property="og:image:height" content="630">',
            '<meta name="twitter:card" content="summary_large_image">',
            '<meta name="twitter:title" content="%s">' % e(TITLE),
            '<meta name="twitter:description" content="%s">' % e(DESC),
            '<meta name="twitter:image" content="%s">' % img,
        ]
        ld = {
            "@context": "https://schema.org", "@type": "VideoGame", "name": "Helpdesk Hero",
            "url": site + "/", "description": DESC, "image": img,
            "genre": ["Simulation", "Educational"], "gamePlatform": "Web browser",
            "applicationCategory": "Game", "operatingSystem": "Any (web browser)",
            "playMode": "SinglePlayer", "inLanguage": "en",
            "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        }
        head.append('<script type="application/ld+json">%s</script>' % json.dumps(ld, separators=(",", ":")))

    page = web / "index.html"
    s = page.read_text(encoding="utf-8")
    s = re.sub(r"<title>.*?</title>", "<title>%s</title>" % e(TITLE), s, count=1, flags=re.S)
    s = s.replace("</head>", "\n".join(head) + "\n</head>", 1)
    body = "".join("<p>%s</p>" % e(p) for p in ABOUT)
    nos = ('<noscript><h1>Helpdesk Hero</h1>%s<p>Turn on JavaScript to play. '
           '<a href="/days/">See every day\'s changes</a>.</p></noscript>' % body)
    s = re.sub(r"(<body[^>]*>)", lambda m: m.group(1) + "\n" + nos, s, count=1)
    page.write_text(s, encoding="utf-8")

    out.mkdir(parents=True, exist_ok=True)
    robots = "User-agent: *\nAllow: /\n"
    if site:
        robots += "Sitemap: %s/sitemap.xml\n" % site
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        urls = "".join("<url><loc>%s%s</loc><lastmod>%s</lastmod><changefreq>daily</changefreq></url>" % (site, p, today)
                       for p in ["/", "/days/"])
        (out / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n'
                                         '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">%s</urlset>\n' % urls)
    (out / "robots.txt").write_text(robots)
    print("seo: %s, site=%s" % (page, site or "(none)"))


if __name__ == "__main__":
    main()
