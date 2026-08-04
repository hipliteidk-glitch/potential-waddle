#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────────────
# ac-query — Quick Termux helper to query the DebugBridge HTTP server
# Requires: DebugBridge plugin installed + curl installed
#
# Usage:
#   ./ac-query              Full status JSON
#   ./ac-query plugins      Just plugin names + enabled state
#   ./ac-query health       Quick health check (is the server up?)
#   ./ac-query check <name> Is a specific plugin loaded?
# ─────────────────────────────────────────────────────────────────────

PORT=2273
BASE="http://localhost:${PORT}"

NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'

case "${1:-status}" in
    status|"")
        curl -s "${BASE}/status" 2>/dev/null | python3 -m json.tool 2>/dev/null \
            || curl -s "${BASE}/status" 2>/dev/null \
            || { echo -e "${RED}Cannot reach DebugBridge server on port ${PORT}${NC}"; \
                 echo "Is DebugBridge plugin enabled in Aliucord?"; exit 1; }
        ;;
    plugins)
        curl -s "${BASE}/plugins" 2>/dev/null \
            || { echo -e "${RED}Cannot reach DebugBridge server${NC}"; exit 1; }
        ;;
    health)
        response=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}/health" 2>/dev/null)
        if [ "$response" = "200" ]; then
            echo -e "${GREEN}✓ DebugBridge HTTP server is running${NC}"
        else
            echo -e "${RED}✗ DebugBridge HTTP server not responding (HTTP $response)${NC}"
            echo "  Check that Discord is running and DebugBridge is enabled"
        fi
        ;;
    check)
        plugin_name="${2:?Usage: ac-query check <pluginname>}"
        status=$(curl -s "${BASE}/status" 2>/dev/null)
        if [ -z "$status" ]; then
            echo -e "${RED}Cannot reach DebugBridge server${NC}"
            exit 1
        fi
        # Check if plugin is in loaded list
        if echo "$status" | python3 -c "
import sys, json
data = json.load(sys.stdin)
name = '${plugin_name}'
for p in data.get('loadedPlugins', []):
    if p['name'].lower() == name.lower():
        state = 'ENABLED' if p['enabled'] else 'DISABLED'
        print(f'✓ {p[\"name\"]} v{p[\"version\"]} — {state}')
        sys.exit(0)
for f in data.get('failedPlugins', []):
    if name.lower() in f['file'].lower():
        print(f'✗ {f[\"file\"]} FAILED: {f[\"error\"]}')
        sys.exit(2)
print(f'✗ Plugin \"{name}\" not found in registry')
sys.exit(1)
" 2>/dev/null; then
            echo -e "${GREEN}Plugin is loaded${NC}"
        else
            rc=$?
            if [ $rc -eq 2 ]; then
                echo -e "${RED}Plugin FAILED to load${NC}"
            else
                echo -e "${YELLOW}Plugin not found in registry${NC}"
            fi
        fi
        ;;
    --help|-h)
        echo "ac-query — Query Aliucord DebugBridge from Termux"
        echo ""
        echo "Commands:"
        echo "  status      Full JSON status (default)"
        echo "  plugins     List plugin names + state"
        echo "  health      Check if DebugBridge HTTP is up"
        echo "  check NAME  Check if a specific plugin is loaded"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run: ac-query --help"
        exit 1
        ;;
esac
