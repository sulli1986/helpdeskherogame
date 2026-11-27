#!/usr/bin/env python3
"""Write the site's welcome page (/index.html) and privacy page (/privacy.html).
Usage: welcome.py SITE_OUT_DIR

The game itself lives at /play.html; the welcome page is what loads first at the site root. It's a
real content page (what the game is, today's changes, how to play), so it's the page that carries
Google AdSense. Never put AdSense on /play.html (policy: no ads on screens without publisher content).
Env: GAME_URL (public https://... address), UMAMI_WEBSITE_ID / GA_MEASUREMENT_ID (analytics),
CONTACT_EMAIL (privacy page contact; optional).
Keep the copy accurate when the game changes; the "Today" card comes from CHANGELOG.md.
"""
import html
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from inject_analytics import tags as analytics_tags  # noqa: E402
from seo import ABOUT, DESC, TITLE, head_tags, site_url  # noqa: E402

ADSENSE = ('<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'
           '?client=ca-pub-1544955300869521" crossorigin="anonymous"></script>')

CSS = """
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif;background:#0b1020;color:#e8ecf5}
main{max-width:820px;margin:0 auto;padding:36px 16px 64px}
a{color:#5cc8ff}
.hero{text-align:center;padding:28px 0 8px}
.hero h1{font-size:clamp(2.2rem,8vw,3.4rem);line-height:1.1;margin:0 0 10px;letter-spacing:-.02em}
.hero p{color:#b6bfd2;font-size:1.1rem;margin:0 auto 22px;max-width:560px}
.play{display:inline-block;background:#5cc8ff;color:#06101f;font-weight:700;font-size:1.25rem;text-decoration:none;
  padding:14px 40px;border-radius:12px}
.play:hover{background:#86d8ff}
.sub{display:block;margin-top:10px;color:#8d97ad;font-size:.9rem}
section{background:#141b2e;border:1px solid #233056;border-radius:12px;padding:18px 20px;margin:22px 0}
h2{margin:0 0 8px;font-size:1.25rem}
.day{color:#8d97ad;font-weight:400;font-size:.95rem}
ul{margin:8px 0 4px;padding-left:20px;color:#cfd6e4} li+li{margin-top:6px}
section p{margin:8px 0;color:#cfd6e4}
footer{margin-top:36px;color:#8d97ad;font-size:.9rem;text-align:center}
footer a{margin:0 6px}
"""


def page(title: str, desc: str, head_extra: str, body: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
{head_extra}
{ADSENSE}
{analytics_tags()}
<style>{CSS}</style></head><body><main>
{body}
<footer><a href="/play.html">Play</a>·<a href="/days/">Every day so far</a>·<a href="/privacy.html">Privacy</a></footer>
</main></body></html>
"""


def today_card() -> str:
    md = Path("CHANGELOG.md").read_text(encoding="utf-8")
    m = re.search(r"^## Day (\d+)\s*[—-]\s*(\S+)\n(.*?)(?=^## |\Z)", md, re.S | re.M)
    if not m:
        return ""
    bullets = "".join("<li>%s</li>" % html.escape(l[2:].strip()) for l in m.group(3).splitlines() if l.startswith("- "))
    return (f'<section><h2>New today <span class="day">Day {m.group(1)} · {html.escape(m.group(2))}</span></h2>'
            f'<ul>{bullets}</ul><p><a href="/days/">See every day\'s changes and play older versions</a></p></section>')


def welcome(site: str) -> str:
    about = "".join("<p>%s</p>" % html.escape(p) for p in ABOUT[1:])
    body = f"""<div class="hero">
<h1>Helpdesk Hero</h1>
<p>{html.escape(ABOUT[0])}</p>
<a class="play" href="/play.html">Play now</a>
<span class="sub">Free · no download · play as a guest or make an account to save your career</span>
</div>
{today_card()}
<section><h2>How it works</h2>{about}</section>
<section><h2>How to play</h2><ul>
<li>Tickets arrive in the queue, from P1 (most urgent, shortest SLA) to P4. Work the urgent ones first.</li>
<li>Open a ticket, read the evidence, then pick your answer with the buttons or keys 1-4.</li>
<li>Some tickets have several steps (diagnose, fix, verify), and network tickets give you a command prompt to type into.</li>
<li>Your tools open in their own tabs beside the ticket, like the separate admin apps a real service desk uses. Lockouts, access requests, new-starter licences, MFA attacks and BitLocker recovery keys are done on the Accounts tab (press T or tap it): find the user, check their details (for an MFA attack, their sign-in log, sessions, MFA methods and inbox rules; for BitLocker, their devices and the key whose ID matches the caller's screen), make the change, then go back to the Ticket tab and press Done. Driver problems are fixed on the Remote Control tab: connect to the user's PC, read Device Manager and Settings, and install the right driver from the vendor's page. Reported emails are dealt with on the Mail Console tab: find the email in the message trace, read its headers, then delete a phish from every mailbox and block its sender or link, or release a legitimate email from quarantine. Printers are sorted out on the Network Map tab: check the print queues, switch ports and DHCP leases, ask the caller to read the printer's screen, then fix it yourself, or log it with the vendor and hold. When the internet is down, the fix step happens on the Network Map too: check the ISP's status page, the modem's lights, the firewall's links, rules and log, and the domain controller's DNS forwarders, DHCP and services, then fix the cause and test it from the user's PC. Laptops for new starters and replacements are set up on the Imaging Bench tab: check the client's laptop standard on the Client Wiki, pick the laptop that's fit to go out (Windows 11 Pro, enough RAM, not reserved for someone else, not one HR asked us to keep, passes its diagnostics), register it in Autopilot with the right group tag, assign it to its user, then wipe and reset it. The Messages tab (C) is where you talk to the caller when a ticket leaves something out: ask an access requester whether they need to edit the files or only view them, or ask a locked-out laptop's owner to read you the key ID on their BitLocker screen. Their reply arrives a moment later, and guessing instead of asking counts against you. The Client Wiki tab (W) is there on every ticket: each client's own page, with who owns each department's files (and their deputy), the client's procedures, laptop standard and servers. Access requests only go ahead when the data's owner or deputy on the wiki approved them. If something doesn't check out, change nothing and refuse or hold instead.</li>
<li>Stuck? Press Ask a Senior under the answers (or H) for a hint. Each step has three, from where to look to exactly what to do, and each one you take costs a quarter of that step's pay.</li>
<li>Faster correct fixes pay more. Wrong calls and SLA breaches cost reputation; lose it all and the client walks.</li>
<li>Press V in the game for what's new, M to mute.</li>
</ul></section>"""
    head = "\n".join(['<meta name="description" content="%s">' % html.escape(DESC),
                      '<meta name="theme-color" content="#0b1020">'] + head_tags(site, "/"))
    return page(TITLE, DESC, head, body)


def privacy(site: str) -> str:
    email = os.environ.get("CONTACT_EMAIL", "").strip()
    contact = (f'email <a href="mailto:{html.escape(email)}">{html.escape(email)}</a>' if email
               else 'message us on our <a href="https://youtube.com/@dailyaigamechange">YouTube channel</a>')
    canon = f'<link rel="canonical" href="{site}/privacy.html">' if site else ""
    body = f"""<h1>Privacy policy</h1>
<p>Helpdesk Hero is a free browser game that an AI improves with one change every day. This page explains what information the site handles and why.</p>
<section><h2>What we collect</h2><ul>
<li><strong>If you play as a guest:</strong> no account and nothing saved on our servers.</li>
<li><strong>If you create an account:</strong> the username you choose and your password. Passwords are never stored as typed; we keep only a salted, one-way hash. We don't ask for your name, email address or date of birth, so please don't use your real name as your username.</li>
<li><strong>Game progress:</strong> your career cash, shifts played, tickets solved, best shift and playtime, so you can carry on where you left off and appear on the leaderboard. Your username and cash total are shown publicly on the leaderboard.</li>
<li><strong>In your browser:</strong> a sign-in token, a backup copy of your latest save and your sound setting are kept in your browser's storage. Clearing your browser data removes them.</li>
</ul></section>
<section><h2>Analytics</h2><p>We count visits and a few game events (for example, starting a shift) with Google Analytics and Umami, and see totals only.</p></section>
<section><h2>Advertising</h2><p>We show ads served by Google AdSense on content pages such as this one (never inside the game) to help cover hosting costs.</p><ul>
<li>Third-party vendors, including Google, use cookies to serve ads based on your prior visits to this site or other websites.</li>
<li>Google's use of advertising cookies enables it and its partners to serve ads to you based on your visits to this and/or other sites on the internet.</li>
<li>You can opt out of personalised advertising in <a href="https://adssettings.google.com" target="_blank" rel="noopener">Google Ads Settings</a>, or opt out of some third-party vendors' cookies at <a href="https://www.aboutads.info/choices" target="_blank" rel="noopener">aboutads.info</a>.</li>
<li>More detail: <a href="https://policies.google.com/technologies/partner-sites" target="_blank" rel="noopener">how Google uses information from sites that use its services</a>.</li>
</ul></section>
<section><h2>Hosting</h2><p>The game and its save server run on <a href="https://bunny.net/privacy" target="_blank" rel="noopener">bunny.net</a>. Like any web host, bunny.net briefly processes your IP address and standard request details to deliver pages and protect against abuse.</p></section>
<section><h2>Your choices</h2><ul>
<li>Play as a guest to keep everything in your browser and nothing on our servers.</li>
<li>Ask us to delete your account and saved progress at any time: {contact}.</li>
<li>Block or clear cookies and local storage in your browser settings.</li>
</ul></section>"""
    return page("Privacy policy · Helpdesk Hero", "How Helpdesk Hero handles your data.",
                '<meta name="description" content="How Helpdesk Hero handles your data: accounts, saves, analytics and advertising.">\n' + canon,
                body)


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    site = site_url(os.environ.get("GAME_URL", ""))
    (out / "index.html").write_text(welcome(site), encoding="utf-8")
    (out / "privacy.html").write_text(privacy(site), encoding="utf-8")
    print("welcome: wrote %s/index.html + privacy.html, site=%s" % (out, site or "(none)"))
