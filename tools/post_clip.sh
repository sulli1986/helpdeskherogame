#!/usr/bin/env bash
# Post a rendered clip via Upload-Post. Once per Day number unless --force.
# Usage: tools/post_clip.sh CLIP_DIR [--force]
# Env: UPLOADPOST_API_KEY, UPLOADPOST_USER, PLATFORMS (default youtube), plus Bunny ZONE/HOST/KEY.
set -euo pipefail
DIR="$1"; FORCE="${2:-}"
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tools/bunny.sh
. "$here/bunny.sh"; bunny_init

if [ -z "${UPLOADPOST_API_KEY:-}" ] || [ -z "${UPLOADPOST_USER:-}" ]; then echo "Upload-Post not configured, skipping"; exit 0; fi
N=$(cat "$DIR/day.txt")
MARK="clips/day-${N}.posted.json"
if [ "$FORCE" != "--force" ] && bunny_exists "$MARK"; then echo "Day ${N} already posted"; exit 0; fi

HOOK="$( (cat "$DIR"/sub_*.txt 2>/dev/null || true) | tr '\n' ' ' | sed 's/  */ /g; s/ $//')"
[ -n "$HOOK" ] || HOOK="$(tr '\n' ' ' < "$DIR/sub.txt" | sed 's/  */ /g; s/ $//')"
TITLE="Day ${N}: ${HOOK} | AI builds an IT helpdesk game daily #Shorts"
TITLE="${TITLE:0:100}"
P="${PLATFORMS:-youtube}"; plat=(); for p in ${P//,/ }; do plat+=(-F "platform[]=$p"); done
# X gets its own short text with the link (280 char limit); Facebook needs a Page ID only if several Pages are connected.
URL="${GAME_URL:-}"
XTEXT="Day ${N} of an AI building an IT helpdesk game, one change a day: ${HOOK}. Play free in your browser: ${URL} #gamedev #ITsupport #MSP #AI #buildinpublic"
XTEXT="${XTEXT:0:280}"
extra=(-F "x_title=${XTEXT}")
FBPAGE="$(printf '%s' "${UPLOADPOST_FACEBOOK_PAGE_ID:-}" | tr -d '[:space:]')"
[ -n "$FBPAGE" ] && extra+=(-F "facebook_page_id=${FBPAGE}")
# A new idempotency key per forced repost so the service doesn't dedupe it.
IDEM="helpdeskhero-day-${N}"; [ "$FORCE" = "--force" ] && IDEM="${IDEM}-$(date +%s)"

code=$(curl -sS -o /tmp/up.json -w '%{http_code}' -X POST https://api.upload-post.com/api/upload \
  -H "Authorization: Apikey $(printf '%s' "$UPLOADPOST_API_KEY" | tr -d '[:space:]')" \
  -H "Idempotency-Key: ${IDEM}" \
  -F "user=$(printf '%s' "$UPLOADPOST_USER" | tr -d '[:space:]')" "${plat[@]}" \
  -F "title=${TITLE}" "${extra[@]}" \
  -F "description=<$DIR/caption.txt" \
  -F "privacyStatus=public" \
  -F "categoryId=20" \
  -F "video=@$DIR/clip.mp4;type=video/mp4")
echo "Day ${N} → Upload-Post HTTP $code"; cat /tmp/up.json; echo
[ "$code" -lt 300 ] || { echo "::error::Upload-Post failed for Day ${N}"; exit 1; }
bunny_put /tmp/up.json "$MARK"
