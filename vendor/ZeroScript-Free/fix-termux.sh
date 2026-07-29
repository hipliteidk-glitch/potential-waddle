#!/data/data/com.termux/files/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# fix-termux.sh - stop the "[roblox] found dead - auto-restarting..." loop.
#
#   bash fix-termux.sh
#
# The loop means config.json still points at Roblox Studio, which cannot exist
# on Android. This script rewrites config.json for the phone - and, unlike a
# bare `cp`, it does NOT depend on any other file being present, so it works
# even in a plain upstream ZeroScript folder.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1

ok()   { printf '\033[92m[fix]\033[0m %s\n' "$*"; }
say()  { printf '\033[96m[fix]\033[0m %s\n' "$*"; }
warn() { printf '\033[93m[fix]\033[0m %s\n' "$*"; }
die()  { printf '\033[91m[fix]\033[0m %s\n' "$*"; exit 1; }

say "Working in: $HERE"

# ── 1. is this even a ZeroScript folder? ───────────────────────────────────
[ -f bridge.py ] || die "bridge.py is not here. cd into the ZeroScript folder first, then re-run."

# ── 2. the no-MCP engine must exist ────────────────────────────────────────
# Upstream ZeroScript does not ship script_server.py. Without it the bridge can
# only talk to MCP servers, so a phone config would have nothing to run.
if [ ! -f script_server.py ]; then
  warn "script_server.py is missing - this looks like the UPSTREAM ZeroScript,"
  warn "which is Roblox-only and cannot work on Android."
  warn ""
  warn "Get the version with phone support instead:"
  warn "  cd ~"
  warn "  git clone https://github.com/hipliteidk-glitch/potential-waddle"
  warn "  cd potential-waddle/vendor/ZeroScript-Free"
  warn "  bash fix-termux.sh"
  exit 1
fi

# ── 3. back up whatever is there now ───────────────────────────────────────
if [ -f config.json ]; then
  cp config.json "config.json.backup.$(date +%s)" 2>/dev/null &&
    say "Backed up your old config.json"
fi

WS="${ZS_WORKSPACE:-$HOME/zs}"
mkdir -p "$WS" || die "could not create the workspace folder: $WS"
[ -e "$WS/README.txt" ] || printf 'Your ZeroScript workspace. The AI can read and write files here.\n' > "$WS/README.txt"

# ── 4. write a phone config directly (no dependency on another file) ───────
cat > config.json <<'JSON'
{
  "target": {
    "id": "phone",
    "kind": "generic",
    "name": "my phone",
    "short": "Phone",
    "offline_hint": "Make sure the bridge is running in Termux (bash start-termux.sh)."
  },
  "servers": {
    "phone": {
      "type": "script",
      "tools": [
        {
          "name": "list_files",
          "description": "List the files in a folder. Use '.' for the top level.",
          "params": { "path": { "type": "string", "description": "folder", "default": "." } },
          "cwd": "{ZS_WORKSPACE}",
          "run": ["ls", "-la", "{path}"]
        },
        {
          "name": "read_file",
          "description": "Show the full contents of a text file.",
          "params": { "path": { "type": "string", "description": "file to read", "required": true } },
          "cwd": "{ZS_WORKSPACE}",
          "run": ["cat", "{path}"]
        },
        {
          "name": "write_file",
          "description": "Create or overwrite a text file with the given content.",
          "params": {
            "path": { "type": "string", "description": "file to write", "required": true },
            "content": { "type": "string", "description": "the full text to put in the file", "required": true }
          },
          "cwd": "{ZS_WORKSPACE}",
          "run": ["python", "-c", "import sys,pathlib;p=pathlib.Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(sys.argv[2]);print(f'wrote {len(sys.argv[2])} chars to {p}')", "{path}", "{content}"]
        },
        {
          "name": "append_file",
          "description": "Append a line of text to the end of a file.",
          "params": {
            "path": { "type": "string", "description": "file to append to", "required": true },
            "content": { "type": "string", "description": "text to append", "required": true }
          },
          "cwd": "{ZS_WORKSPACE}",
          "run": ["python", "-c", "import sys,pathlib;p=pathlib.Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True);f=p.open('a');f.write(sys.argv[2]+chr(10));f.close();print('appended to '+str(p))", "{path}", "{content}"]
        },
        {
          "name": "search_text",
          "description": "Search for a text pattern and show matching lines with line numbers.",
          "params": {
            "pattern": { "type": "string", "description": "text to find", "required": true },
            "path": { "type": "string", "description": "folder or file to search", "default": "." }
          },
          "cwd": "{ZS_WORKSPACE}",
          "run": ["grep", "-rn", "--", "{pattern}", "{path}"]
        },
        {
          "name": "phone_status",
          "description": "Show the date and free space on the phone.",
          "cwd": "{ZS_WORKSPACE}",
          "run": ["sh", "-c", "date; echo; df -h ."]
        }
      ]
    }
  }
}
JSON

# ── 5. prove it is no longer Roblox ────────────────────────────────────────
if grep -q "launch_studio_mcp" config.json; then
  die "config.json still references Roblox - the rewrite did not take."
fi

ok "config.json now targets your phone (no Roblox, no MCP)."
ok "Workspace: $WS"
echo
say "Now start it with:"
say "    bash start-termux.sh"
say "(or, if that file is missing:  python bridge.py )"
echo
say "You should see:  ready 6 tools available - my phone connected"
say "If you EVER see '[roblox]' again, re-run this script."
