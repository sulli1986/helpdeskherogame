# Vision

There is no task list. Each day the agent plays the current game, reads the recent CHANGELOG and decides
for itself what single change would make Helpdesk Hero most better for players today: a new mechanic, a
new tool or a step towards one, a fix for something clunky, wrong or confusing, a better existing system,
or a site page. Pick what a player would notice and value most, not what's easiest.

**North star (David, Day 8):** a hands-on service desk simulator: the player does the work in fake tools
instead of picking answers. Our own names and design throughout (see "Originality" in CLAUDE.md).
Directions this can grow in (not a to-do list, and not the only options):
- **Toolbox:** admin tools beside the ticket: **Accounts** (users, groups, licences, sign-in methods),
  **Remote Control** (a mock desktop of the user's PC or a server), **Network Map** (the client's ISP link,
  firewall, switches and servers with live status), **Imaging Bench** (build and hand out new PCs), **Mail Console**
- **People:** callers on the phone, voicemail, and **Messages** with the user to get missing details
- **Client Wiki:** per-client notes (servers, IPs, printers, procedures, where credentials live)
- **Ask a Senior:** a step-by-step nudge that costs part of the ticket's pay
- Later: a PSA with ticket notes, a security alert queue, client contracts, careers, streaks and achievements

## Design rules
**Sim, not quiz:** favour new mechanics, interactive tools and improvements to existing systems over new
question types. Add a new ticket type at most one day in three (check the last few CHANGELOG entries).
**Ship every day:** a day's work can be any size, including groundwork for a bigger feature over several days
(tracked in NOTES.md), but every day must ship something players get, and the game must always work.
**Toolbox layout (David, Day 9):** each tool opens as its own tab (a separate window on wide screens later)
beside the Ticket tab, like real IT tooling; never inline inside the ticket. New tools add a tab.
**Pacing:** a ticket should take a real player 1-3 minutes, so a 10-minute shift is about 12-15 tickets. Keep
SLAs and arrival rates realistic for that whenever new steps or tools make tickets longer.
**Site:** real content pages (guides, glossary, ticket walkthroughs) give the ads somewhere to live.
