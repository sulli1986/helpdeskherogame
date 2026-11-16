# Roadmap

Ordered loosely. The daily agent takes the top unchecked item unless something better is obvious.
Every day should add something new or noticeably improve something players already use.

**Balance rule:** the game should grow as a sim, not a quiz. Favour new mechanics, interactive
tools and improvements to existing systems over new question types. Add a new ticket type at most
one day in three; the other days build things like the items in "Mechanics" below.

**North star (David, Day 8):** a hands-on service desk simulator in the spirit of servicedesk-simulator.com:
the player does the work in fake tools instead of picking answers. Remote-desktop "VMs" of the user's PC
and the client's servers, an Active Directory / Entra admin console, a PSA ticket system with notes, callers
on the phone and coworkers in chat, a security (SOC) queue later. Build it in small playable steps, one per day.
**Pacing:** a ticket should take a real player 1-3 minutes, so a 10-minute shift is about 12-15 tickets. Keep
SLAs and arrival rates realistic for that whenever new steps or tools make tickets longer.
**Site:** more real content pages (guides, glossary) give the ads somewhere to live; see "Site" below.

- [x] Day 1: ticket queue, SLA timers, 6 ticket types, scoring + reputation, shift report, login/save, leaderboard
- [x] Day 2: Sound: procedural blips for new ticket, resolve, wrong call, SLA warning (code-built AudioStreamWAV), M to mute
- [x] Day 3: New ticket type: MFA fatigue (user approving pushes they didn't start) → revoke sessions, reset, number matching

## Mechanics (take these first)
- [x] Pacing: 10-minute shifts, longer SLAs (plus time per extra step), slower arrivals that hold off while 3 tickets sit unopened
- [ ] Virtual machines, step 1: a "Remote desktop" window onto the user's PC (a mock Windows desktop built from Controls: taskbar, Start, a Settings > Network page, Services, Device Manager, Event Viewer). Use it for the network and printer tickets' fix steps: the player finds and clicks the actual fix (e.g. restart the DHCP Server service on DC01) instead of choosing an option
- [ ] Virtual machines, step 2: a VM list (PC-USER, DC01, PRINT01, FW01) to connect to; each ticket says which machines are involved, and connecting to the wrong one wastes time
- [ ] Virtual machines, step 3: Active Directory Users and Computers on DC01 (find user, unlock, reset password, group membership) used by lockout and share-access tickets
- [ ] Virtual machines, step 4: Services / Event Viewer / Task Manager actions with real consequences (stop the wrong service and another ticket arrives)
- [x] Virtual PC terminal, step 1: on network tickets, the evidence starts hidden and the player types real commands (ipconfig, ping, nslookup, tracert) into a simulated command prompt to reveal it. Unknown commands get a realistic error
- [x] Multi-step tickets, step 1: network tickets are diagnose, then fix (the fix step reveals server/router evidence), paying for each step
- [x] Multi-step tickets, step 2: add a verify step (after the fix the command prompt shows the healed network; the player runs the test that proves it)
- [x] Multi-step tickets, step 3: make printer tickets multi-step too (diagnose the queue/driver/network fault, then fix it on the print server)
- [x] Admin console, step 1: a mock user-admin panel (account status, MFA methods, sessions, mailbox rules); MFA fatigue tickets are contained by ticking the right actions and applying them
- [ ] Requirements gathering: project/new-starter tickets where the client's request is vague; pick which questions to ask (limited budget of questions), then spec the solution from the answers
- [ ] Incident checklist: put containment/recovery steps in the right order (drag or number them); used by the ransomware event
- [ ] Virtual PC terminal, step 2: extend the command prompt to printer and lockout tickets (Get-Printer, net user, Get-ADUser, etc.)
- [ ] Admin console, step 2: shared mailbox and licence tickets done in the console (assign licence, Full Access, Send As)
- [ ] Admin console, step 3: lockout tickets done in the console (verify the caller, unlock, reset, force change at next logon), with actions that must be applied in order
- [ ] Ticket notes: after fixing, pick the right resolution note/category for the PSA; good notes give a small rep bonus

## Systems
- [ ] Phone queue: a ringing call that must be picked up within 15s or it becomes a P2 voicemail ticket
- [ ] Upgrades shop between shifts: spend career cash on RMM (+10s SLA), password self-service (fewer lockouts), documentation wiki (hint button)
- [ ] Client roster: each client has a contract value and happiness; breaching one client repeatedly loses only that contract
- [ ] Combo streak: consecutive correct answers multiply pay, shown in the top bar
- [ ] Hire a Tier 1 tech: auto-resolves P4 tickets slowly in the background, costs wages per shift
- [ ] Daily challenge: same seeded shift for everyone each day, separate leaderboard
- [ ] Touch-friendly layout tweaks for phones
- [ ] Server-side cash sanity check (cap gain per second of playtime)
- [ ] Ransomware incident event: a P1 storm mid-shift with an incident-response checklist
- [ ] Career levels: Tier 1 → Tier 2 → Tier 3 → Service Manager, unlocking harder ticket types

## Site (content pages for players and search; AdSense only on these, never on /play.html)
- [ ] Guides, step 1: `/guides/` index plus 3 original how-to pages that match the game (troubleshooting "no internet": ipconfig, ping, nslookup, tracert; reading phishing email headers: SPF, DKIM, DMARC; MFA fatigue attacks and number matching), generated at build time like the welcome page, linked from the welcome page and the sitemap
- [ ] Guides, step 2: three more guides (print server troubleshooting, account lockouts in AD, M365 licences explained)
- [ ] Glossary page: plain-English definitions of the terms the game uses (SLA, MSP, DHCP, DNS forwarder, PSA, RMM, Entra ID...), linked from guides
- [ ] Ticket walkthroughs: one page per ticket type explaining the evidence and why each fix is right, linked from the in-game result ("Learn more")

## New ticket types (at most one day in three)
- [ ] New ticket type: backup failure (Veeam/job log) → pick the cause (repo full, VSS error, credentials expired)
- [ ] New ticket type: security baseline audit question (app control, patching, macros, admin privileges, MFA)
- [ ] New ticket type: certificate expired on the client's website / VPN
