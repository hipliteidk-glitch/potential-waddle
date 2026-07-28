#!/usr/bin/env bash
#
# Publish WELLSPRING to PageDrop (https://pagedrop.io) and print the live URL.
#
# PageDrop hosts a single self-contained HTML file, which is exactly what this
# game is -- no signup, no API key, no build step.
#
# Usage:
#   ./deploy/pagedrop.sh                 # 3-day link, random slug
#   ./deploy/pagedrop.sh -p wellspring   # ask for wellspring.pagedrop.io
#   ./deploy/pagedrop.sh -t 1d           # shorter time-to-live
#   ./deploy/pagedrop.sh -w hunter2      # password-protect it
#
# Note: the API only offers short TTLs (1h / 1d / 3d / once). For a permanent
# home use GitHub Pages, Netlify or Vercel -- see the README.

set -euo pipefail

# Resolve the game relative to this script, falling back to the current
# directory so the script still works if it is copied elsewhere.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
GAME=""
for cand in "$SCRIPT_DIR/../games/wellspring.html" "./games/wellspring.html" "./wellspring.html"; do
  if [[ -s "$cand" ]]; then GAME="$cand"; break; fi
done
TTL="3d"
CUSTOM_PATH=""
PASSWORD=""

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while getopts "t:p:w:f:h" opt; do
  case "$opt" in
    t) TTL="$OPTARG" ;;
    p) CUSTOM_PATH="$OPTARG" ;;
    w) PASSWORD="$OPTARG" ;;
    f) GAME="$OPTARG" ;;
    h) usage ;;
    *) echo "try -h" >&2; exit 2 ;;
  esac
done

if [[ -z "$GAME" || ! -s "$GAME" ]]; then
  echo "error: could not find games/wellspring.html (pass one with -f)" >&2
  exit 1
fi

case "$TTL" in
  1h|1d|3d|once) ;;
  *) echo "error: ttl must be one of 1h, 1d, 3d, once (got '$TTL')" >&2; exit 2 ;;
esac

command -v python3 >/dev/null || { echo "error: python3 required" >&2; exit 1; }
command -v curl    >/dev/null || { echo "error: curl required" >&2; exit 1; }

# Build the JSON body with python so the HTML is escaped correctly.
PAYLOAD="$(mktemp)"
trap 'rm -f "$PAYLOAD"' EXIT

python3 - "$GAME" "$TTL" "$CUSTOM_PATH" "$PASSWORD" > "$PAYLOAD" <<'PY'
import json, sys
path, ttl, custom, password = sys.argv[1:5]
html = open(path, encoding="utf-8").read()

if len(html) > 16 * 1024 * 1024:
    sys.exit("error: HTML exceeds PageDrop's 16MB limit")
if "<!DOCTYPE" not in html and "<html" not in html:
    sys.exit("error: file does not look like a complete HTML document")

body = {"html": html, "ttl": ttl, "fileName": "wellspring.html", "visibility": "private"}
if custom:
    body["customPath"] = custom
if password:
    body["password"] = password
json.dump(body, sys.stdout)
PY

echo "Uploading $(wc -c < "$GAME" | tr -d ' ') bytes to PageDrop (ttl=$TTL)..."

RESPONSE="$(curl -fsS -X POST https://pagedrop.io/api/upload \
  -H "Content-Type: application/json" \
  --data-binary @"$PAYLOAD")" || {
    echo "error: upload request failed (no network, or PageDrop rejected it)" >&2
    exit 1
  }

python3 - "$RESPONSE" <<'PY'
import json, sys
try:
    r = json.loads(sys.argv[1])
except json.JSONDecodeError:
    sys.exit("error: unexpected response:\n" + sys.argv[1][:400])

if not r.get("success"):
    sys.exit(f"error: {r.get('code','?')}: {r.get('error','unknown error')}")

d = r["data"]
print()
print("  LIVE:  " + d["url"])
if d.get("duplicate"):
    print("  (identical content was already uploaded; reusing that link)")
print()
print("  Share it, or open it on your phone -- one finger pulls, two push.")
PY
