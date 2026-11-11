# Roadmap

Ordered loosely. The daily agent takes the top unchecked item unless something better is obvious.
Every day should add something new or noticeably improve something players already use.

**Balance rule:** the game should grow as a sim, not a quiz. Favour new mechanics, interactive
tools and improvements to existing systems over new question types. Add a new ticket type at most
one day in three; the other days build things like the items in "Mechanics" below.

- [x] Day 1: ticket queue, SLA timers, 6 ticket types, scoring + reputation, shift report, login/save, leaderboard
- [x] Day 2: Sound: procedural blips for new ticket, resolve, wrong call, SLA warning (code-built AudioStreamWAV), M to mute
- [x] Day 3: New ticket type: MFA fatigue (user approving pushes they didn't start) → revoke sessions, reset, number matching

## Mechanics (take these first)
- [x] Virtual PC terminal, step 1: on network tickets, the evidence starts hidden and the player types real commands (ipconfig, ping, nslookup, tracert) into a simulated command prompt to reveal it. Unknown commands get a realistic error
- [ ] Multi-step tickets: diagnose, then fix, then verify (two or three questions on one ticket, pay for each step)
- [ ] Admin console, step 1: a mock user-admin panel (account status, MFA methods, sessions, mailbox rules) where the player fixes lockout/MFA tickets by clicking the right actions in the right order, instead of picking one option
- [ ] Requirements gathering: project/new-starter tickets where the client's request is vague; pick which questions to ask (limited budget of questions), then spec the solution from the answers
- [ ] Incident checklist: put containment/recovery steps in the right order (drag or number them); used by the ransomware event
- [ ] Virtual PC terminal, step 2: extend the command prompt to printer and lockout tickets (Get-Printer, net user, Get-ADUser, etc.)
- [ ] Admin console, step 2: shared mailbox and licence tickets done in the console (assign licence, Full Access, Send As)
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

## New ticket types (at most one day in three)
- [ ] New ticket type: backup failure (Veeam/job log) → pick the cause (repo full, VSS error, credentials expired)
- [ ] New ticket type: security baseline audit question (app control, patching, macros, admin privileges, MFA)
- [ ] New ticket type: certificate expired on the client's website / VPN
