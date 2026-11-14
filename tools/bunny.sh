# Bunny Storage helpers. Source this file; needs ZONE, HOST, KEY in the environment.
# shellcheck shell=bash

bunny_init() {
  _trim() { printf '%s' "$1" | tr -d '[:space:]'; }
  KEY="$(_trim "${KEY:-}")"; ZONE="$(_trim "${ZONE:-}")"; HOST="$(_trim "${HOST:-}")"
  HOST="${HOST#*://}"; HOST="${HOST%%/*}"; HOST="${HOST:-storage.bunnycdn.com}"
  ZONE="${ZONE#/}"; ZONE="${ZONE%/}"
  [ -n "$ZONE" ] && [ -n "$KEY" ] || { echo "::error::Missing BUNNY_STORAGE_ZONE / BUNNY_STORAGE_PASSWORD"; return 1; }
}

_bunny_ctype() {
  case "$1" in
    *.wasm) echo application/wasm ;;
    *.js)   echo application/javascript ;;
    *.html) echo "text/html; charset=utf-8" ;;
    *.png)  echo image/png ;;
    *.mp4)  echo video/mp4 ;;
    *.txt)  echo "text/plain; charset=utf-8" ;;
    *.json) echo application/json ;;
    *.xml)  echo "application/xml; charset=utf-8" ;;
    *)      echo application/octet-stream ;;
  esac
}

# bunny_put LOCAL_FILE REMOTE_PATH
bunny_put() {
  curl -sSf --retry 3 -X PUT "https://${HOST}/${ZONE}/$2" -H "AccessKey: ${KEY}" \
    -H "Content-Type: $(_bunny_ctype "$2")" --data-binary "@$1" > /dev/null
}

# bunny_put_dir LOCAL_DIR REMOTE_PREFIX   (flat directory, like a Godot web export)
bunny_put_dir() {
  local f
  for f in "$1"/*; do
    [ -f "$f" ] || continue
    echo "PUT $2/$(basename "$f")"
    bunny_put "$f" "$2/$(basename "$f")"
  done
}

# bunny_delete REMOTE_PATH
bunny_delete() {
  curl -sSf --retry 3 -X DELETE "https://${HOST}/${ZONE}/$1" -H "AccessKey: ${KEY}" > /dev/null
}

# bunny_exists REMOTE_PATH  -> exit 0 if the object exists
bunny_exists() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' "https://${HOST}/${ZONE}/$1" -H "AccessKey: ${KEY}")" = "200" ]
}
