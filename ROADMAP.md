# Roadmap

Ordered loosely. The daily agent takes the top unchecked item unless something better is obvious.
Every day should add something new or noticeably improve something players already use.

- [x] Day 1: ticket queue, SLA timers, 6 ticket types, scoring + reputation, shift report, login/save, leaderboard
- [x] Day 2: Sound: procedural blips for new ticket, resolve, wrong call, SLA warning (code-built AudioStreamWAV), M to mute
- [x] Day 3: New ticket type: MFA fatigue (user approving pushes they didn't start) → revoke sessions, reset, number matching
- [ ] Phone queue: a ringing call that must be picked up within 15s or it becomes a P2 voicemail ticket
- [ ] Upgrades shop between shifts: spend career cash on RMM (+10s SLA), password self-service (fewer lockouts), documentation wiki (hint button)
- [ ] New ticket type: backup failure (Veeam/job log) → pick the cause (repo full, VSS error, credentials expired)
- [ ] Client roster: each client has a contract value and happiness; breaching one client repeatedly loses only that contract
- [ ] Combo streak: consecutive correct answers multiply pay, shown in the top bar
- [ ] New ticket type: security baseline audit question (app control, patching, macros, admin privileges, MFA)
- [ ] Hire a Tier 1 tech: auto-resolves P4 tickets slowly in the background, costs wages per shift
- [ ] Daily challenge: same seeded shift for everyone each day, separate leaderboard
- [ ] New ticket type: certificate expired on the client's website / VPN
- [ ] Multi-step tickets: diagnose, then fix (two questions on one ticket)
- [ ] Touch-friendly layout tweaks for phones
- [ ] Server-side cash sanity check (cap gain per second of playtime)
- [ ] Ransomware incident event: a P1 storm mid-shift with an incident-response checklist
- [ ] Career levels: Tier 1 → Tier 2 → Tier 3 → Service Manager, unlocking harder ticket types
