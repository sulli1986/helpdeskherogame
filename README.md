# Helpdesk Hero

An MSP helpdesk sim in the browser. Work the ticket queue, beat the SLA, keep the clients. Godot 4.5 (GL Compatibility, single-threaded web export), hosted on bunny.net, saves in Bunny Database. One improvement ships every day. See `CHANGELOG.md`; rules for the daily agent are in `CLAUDE.md`.

## How to play
Click a ticket (or Tab / ↑↓), read the evidence, pick the fix with 1-4, Enter for the next ticket. V shows what's new.

## Bunny setup (one-off)
1. **Storage zone** + **pull zone** pointing at it (this serves the game). Add your domain to the pull zone.
2. **Database**: `bunny db create` (separate from Streetstorm's).
3. **Edge Script** (standalone): paste `api/edge-script.ts`, link the database (sets `BUNNY_DATABASE_URL` / `BUNNY_DATABASE_AUTH_TOKEN`). Optional env `ALLOWED_ORIGIN=https://your-game-domain`. Tables create themselves on first request.

## GitHub settings → Secrets and variables → Actions
| Name | Type | Value |
|---|---|---|
| `BUNNY_STORAGE_PASSWORD` | secret | Storage zone → FTP & API access → Password |
| `BUNNY_API_KEY` | secret | Account API key (purge + edge script deploy) |
| `BUNNY_STORAGE_ZONE` | variable | Storage zone name |
| `BUNNY_STORAGE_HOST` | variable | e.g. `syd.storage.bunnycdn.com` (match the zone's primary region) |
| `BUNNY_PULLZONE_ID` | variable | Numeric pull zone ID |
| `BUNNY_SCRIPT_ID` | variable | Numeric edge script ID (optional; enables API auto-deploy) |
| `GAME_API_URL` | variable | Edge script URL, e.g. `https://helpdeskhero-api.b-cdn.net` |
| `GAME_URL` | variable | Public game URL (used in clip captions and posts) |
| `UMAMI_WEBSITE_ID` | variable | Optional: Umami website ID for analytics |
| `GA_MEASUREMENT_ID` | variable | Optional: Google Analytics 4 measurement ID (`G-…`, from Admin → Data streams) |
| `UPLOADPOST_API_KEY` | secret | Optional: Upload-Post key for daily clip posting |
| `UPLOADPOST_USER` | variable | Upload-Post profile name |
| `UPLOADPOST_PLATFORMS` | variable | Default `youtube x facebook` |

Push to `main` → CI exports the web build, uploads to storage, archives `/days/day-N/`, purges the pull zone, deploys the edge script (if `BUNNY_SCRIPT_ID` is set), and renders the daily clip to `/clips/day-N.mp4`.

## Local dev
`godot --headless --export-release "Web" build/web/index.html`, then serve `build/web`. The API defaults to `http://localhost:8787` when `GAME_API` isn't set.
Preview the clip autopilot: `godot -- --demo` (portrait) or `godot -- --demo --landscape`.
