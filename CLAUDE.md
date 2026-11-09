# Helpdesk Hero — daily change rules

Godot 4.5 web game: an MSP helpdesk sim, hosted on bunny.net. Every day an agent makes **exactly one** improvement. Sister project of Streetstorm (`sulli1986/dailygamechange`), same pipeline.

## Layout
- `scripts/main.gd` — entry point (Control): screens, career state, saves, summary panel
- `scripts/title.gd` — title screen: login/register/guest, career line, leaderboard
- `scripts/desk.gd` — a shift: queue, SLA timers, ticket view, answering, scoring, reputation
- `scripts/tickets.gd` — ticket generator; one `_make_<kind>()` per ticket type, listed in `KINDS`
- `scripts/ui.gd` — colours, theme and small UI builders (static)
- `scripts/whats_new.gd` — in-game changelog panel (V)
- `scripts/demo.gd` — autopilot for the daily promo clip (`-- --demo`), portrait 720x1280
- `scripts/api.gd` — HTTP client for the edge script
- `api/edge-script.ts` — Bunny Edge Script (Deno) + Bunny Database
- `.github/workflows/deploy.yml` — export + upload on push to `main`; archives the build to `/days/day-N/`, rebuilds `/days/index.html`, renders + posts the clip
- `.github/workflows/backfill.yml` — manual: rebuild past days from git history, re-render/repost clips
- `tools/test_tickets.gd` — ticket sanity test (structure, answer range, variety, no region-specific terms)
- `tools/` — `bunny.sh` (storage helpers), `make_clip.sh`, `clip_text.py`, `clip_filter.py`, `post_clip.sh`, `days_index.py`, `day_commits.py`, `inject_demo.py`, `inject_umami.py`

## Daily change procedure
1. Read `CHANGELOG.md` and `ROADMAP.md`. Pick the top unchecked roadmap item, or a better small idea if one is clearly more valuable.
2. Make ONE focused change (one feature or one fix). Keep the diff small and readable.
3. Everything stays code-built: Control nodes, StyleBoxFlat, procedural audio. No binary assets.
4. Renderer is GL Compatibility, single-threaded web export. Don't add anything needing threads or SharedArrayBuffer.
5. **Ticket content must be technically correct.** Players include real IT/MSP people. Keep it global and generic: no country- or city-specific businesses, ISPs or slang. Fictional, generic client businesses only (e.g. "Clearwater Dental"); never real company names as clients (vendors like Microsoft/Xero in headers are fine).
6. New persisted fields: add to `career` in main.gd (it's saved whole), and whitelist in `cleanSave()` in `api/edge-script.ts`. Never change existing columns destructively.
7. Validate: `godot --headless --import --quit`, then a short run `godot --headless --quit-after 600` and `godot --headless --quit-after 600 -- --demo`, then `godot --headless --export-release "Web" build/web/index.html`. None may print `SCRIPT ERROR` / `Parse Error`.
   Also run `godot --headless -s tools/test_tickets.gd`; it must print `0 failure(s)` (CI runs it too and blocks the deploy on failure). When you add a ticket type, it's covered automatically via `KINDS`.
7b. **Fact-check before committing.** Have an independent reviewer (a fresh subagent that didn't write the change) read the diff and check: every ticket's right answer genuinely follows from its evidence in every random variant; the wrong options are actually wrong; explanations are accurate for current Microsoft 365 / Windows / networking practice; numbers and game logic (SLA, pay, rep, save fields) add up; nothing country-specific. Fix what it finds. If you can't get it to a clean result, don't push: revert and report.
8. Add an entry at the top of `CHANGELOG.md` as `## Day N — YYYY-MM-DD` (Australia/Perth date) followed by 1–3 `- ` bullets written for players (what's new and how to try it, no code talk). This file is shown in-game by the "What's new" panel, and the heading becomes the build's version label. Tick the roadmap item.
9. If the change is visible, make sure the demo shows it (e.g. force the new ticket type early with `gen.make("kind")`, or add a beat to TIMELINE in `scripts/demo.gd`). Keep END_AT under 59s. The clip's caption comes from your first CHANGELOG bullet, so lead with the hook (text before a colon is the on-screen line).
10. Commit to `main` with message `Day N: <change>` and push. CI deploys.

## Don't
- Don't commit secrets. Bunny keys live in GitHub secrets/vars only.
- Don't break old saves: older day builds share the database and send no newer fields; the server ignores out-of-order saves via `seq`.
- Don't rewrite large files for style. Don't change controls without updating the title screen's "How to play" line.
