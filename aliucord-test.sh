#!/data/data/com.termux/files/usr/bin/bash
# ─────────────────────────────────────────────────────────────────────
# Aliucord Plugin Tester — Termux Script
# ─────────────────────────────────────────────────────────────────────
# Tests whether an Aliucord plugin loads successfully by:
#   1. Deploying the plugin .zip to /sdcard/Aliucord/plugins/
#   2. Force-restarting Discord
#   3. Reading logcat for Aliucord PluginManager entries
#   4. Checking for crash logs
#
# PREREQUISITES (run once in Termux):
#   termux-setup-storage          # Grant storage access
#   pkg install android-tools     # For logcat, am, etc.
#
# USAGE:
#   ./aliucord-test.sh <plugin.zip>
#   ./aliucord-test.sh --logcat-only          # Just read current logs
#   ./aliucord-test.sh --status               # List installed plugins
#   ./aliucord-test.sh --crash-check          # Show latest crash logs
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Paths (from Aliucord Constants.java) ──
ALIUCORD_BASE="/sdcard/Aliucord"
PLUGINS_DIR="${ALIUCORD_BASE}/plugins"
CRASHLOGS_DIR="${ALIUCORD_BASE}/crashlogs"
SETTINGS_DIR="${ALIUCORD_BASE}/settings"

# ── Discord package ──
DISCORD_PKG="com.discord"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ──
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
header(){ echo -e "\n${BOLD}══ $* ══${NC}"; }

check_prereqs() {
    local missing=0

    if [ ! -d "/sdcard/Android" ] && [ ! -d "$ALIUCORD_BASE" ]; then
        fail "Storage not accessible. Run: termux-setup-storage"
        missing=1
    fi

    if ! command -v logcat &>/dev/null; then
        fail "logcat not found. Run: pkg install android-tools"
        missing=1
    fi

    if [ ! -d "$PLUGINS_DIR" ]; then
        warn "Aliucord plugins directory not found at: $PLUGINS_DIR"
        warn "Is Aliucord installed and has it been opened at least once?"
        info "Creating plugins directory..."
        mkdir -p "$PLUGINS_DIR" 2>/dev/null || {
            fail "Cannot create $PLUGINS_DIR — grant storage permissions first"
            missing=1
        }
    fi

    # Check if Discord is installed
    if ! pm list packages 2>/dev/null | grep -q "$DISCORD_PKG"; then
        warn "Discord ($DISCORD_PKG) does not appear to be installed"
    fi

    return $missing
}

# ── Command: status ──
cmd_status() {
    header "Aliucord Plugin Status"

    echo -e "\n${BOLD}Installed plugin files:${NC}"
    if [ -d "$PLUGINS_DIR" ]; then
        local count=0
        while IFS= read -r f; do
            local name size
            name=$(basename "$f")
            size=$(du -h "$f" 2>/dev/null | cut -f1)
            echo -e "  ${CYAN}•${NC} $name  (${size})"
            ((count++))
        done < <(find "$PLUGINS_DIR" -maxdepth 1 -name "*.zip" -type f 2>/dev/null | sort)
        [ "$count" -eq 0 ] && warn "  No .zip plugins found"
        echo -e "\n  Total: ${BOLD}${count}${NC} plugin(s)"
    else
        fail "Plugins directory does not exist"
    fi

    echo -e "\n${BOLD}Crash logs:${NC}"
    if [ -d "$CRASHLOGS_DIR" ]; then
        local crash_count
        crash_count=$(find "$CRASHLOGS_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | wc -l)
        echo "  $crash_count crash log(s) on disk"
        if [ "$crash_count" -gt 0 ]; then
            local latest
            latest=$(ls -t "$CRASHLOGS_DIR"/*.txt 2>/dev/null | head -1)
            echo -e "  Latest: ${YELLOW}$(basename "$latest")${NC}"
        fi
    else
        echo "  No crashlogs directory (good — no crashes recorded)"
    fi

    echo -e "\n${BOLD}Safe mode:${NC}"
    local settings_file="${SETTINGS_DIR}/Aliucord.json"
    if [ -f "$settings_file" ]; then
        if grep -q '"AC_SAFE_MODE"[[:space:]]*:[[:space:]]*true' "$settings_file" 2>/dev/null; then
            warn "  Safe mode is ENABLED — external plugins will NOT load!"
        else
            ok "  Safe mode is OFF"
        fi
    else
        echo "  Settings file not found (Aliucord may not have run yet)"
    fi
}

# ── Command: logcat-only ──
cmd_logcat() {
    header "Aliucord Logcat Output"
    info "Reading logcat for Aliucord-related entries..."
    echo ""

    # Aliucord Logger formats as: "[ModuleName] message"
    # It also logs to logcat via android.util.Log with tag from AppLog
    # We grep for multiple patterns to catch everything
    logcat -d 2>/dev/null | grep -iE '\[PluginManager\]|\[Aliucord\]|Aliucord|aliucord' | tail -80 || {
        warn "No Aliucord entries found in current logcat buffer"
    }
}

# ── Command: crash-check ──
cmd_crash_check() {
    header "Crash Log Check"

    if [ ! -d "$CRASHLOGS_DIR" ]; then
        ok "No crashlogs directory exists — no crashes recorded"
        return
    fi

    local crash_files
    crash_files=$(find "$CRASHLOGS_DIR" -maxdepth 1 -name "*.txt" -type f 2>/dev/null | sort -r)

    if [ -z "$crash_files" ]; then
        ok "No crash logs found"
        return
    fi

    local latest
    latest=$(echo "$crash_files" | head -1)
    warn "Latest crash log: $(basename "$latest")"
    echo ""
    echo -e "${BOLD}── Contents ──${NC}"
    head -40 "$latest"
    echo ""

    # Try to identify the offending plugin
    local bad_plugin
    bad_plugin=$(grep -oP 'com\.aliucord\.\w+|plugin.*?(\w+)' "$latest" 2>/dev/null | head -5)
    if [ -n "$bad_plugin" ]; then
        echo -e "${BOLD}Possible plugin involvement:${NC}"
        echo "$bad_plugin" | sort -u | sed 's/^/  /'
    fi
}

# ── Command: deploy + test ──
cmd_test() {
    local plugin_zip="$1"

    if [ ! -f "$plugin_zip" ]; then
        fail "Plugin file not found: $plugin_zip"
        exit 1
    fi

    local plugin_name
    plugin_name=$(basename "$plugin_zip" .zip)

    # Validate the zip has a manifest.json
    if ! unzip -l "$plugin_zip" 2>/dev/null | grep -q "manifest.json"; then
        fail "Plugin zip does not contain manifest.json"
        info "A valid Aliucord plugin zip must have a manifest.json at the root"
        exit 1
    fi

    # Extract plugin name from manifest for better reporting
    local manifest_name
    manifest_name=$(unzip -p "$plugin_zip" manifest.json 2>/dev/null | grep -oP '"name"\s*:\s*"\K[^"]+' | head -1)
    if [ -n "$manifest_name" ]; then
        plugin_name="$manifest_name"
        info "Plugin name from manifest: ${BOLD}${plugin_name}${NC}"
    else
        info "Plugin filename: ${BOLD}${plugin_name}${NC} (could not parse manifest name)"
    fi

    # ── Step 1: Deploy ──
    header "Step 1: Deploying Plugin"
    local dest="${PLUGINS_DIR}/${plugin_name}.zip"

    if [ -f "$dest" ]; then
        warn "Existing plugin found at: $dest"
        info "Backing up to: ${dest}.bak"
        cp "$dest" "${dest}.bak"
    fi

    cp "$plugin_zip" "$dest"
    ok "Copied to: $dest"

    # Verify the file is there and readable
    local deployed_size
    deployed_size=$(du -h "$dest" | cut -f1)
    ok "Deployed size: $deployed_size"

    # ── Step 2: Clear logcat buffer ──
    header "Step 2: Preparing Logcat"
    logcat -c 2>/dev/null && ok "Logcat buffer cleared" || warn "Could not clear logcat"

    # ── Step 3: Force restart Discord ──
    header "Step 3: Restarting Discord"
    info "Force-stopping $DISCORD_PKG..."
    am force-stop "$DISCORD_PKG" 2>/dev/null && ok "Force-stopped" || warn "Could not force-stop (may not be running)"

    sleep 1

    info "Launching Discord..."
    # Use monkey to launch via default intent (same as tapping the icon)
    monkey -p "$DISCORD_PKG" -c android.intent.category.LAUNCHER 1 2>/dev/null >/dev/null \
        && ok "Discord launch event sent" \
        || warn "Could not launch Discord via monkey"

    # ── Step 4: Wait and collect logs ──
    header "Step 4: Collecting Logs"
    info "Waiting 8 seconds for Aliucord to initialize and load plugins..."
    sleep 8

    echo ""
    echo -e "${BOLD}── Aliucord PluginManager Log ──${NC}"

    local log_output
    log_output=$(logcat -d 2>/dev/null | grep -iE '\[PluginManager\]|\[Aliucord\]|aliucord' | tail -60)

    if [ -z "$log_output" ]; then
        warn "No Aliucord log entries found. Possible reasons:"
        echo "  • Discord hasn't fully started yet"
        echo "  • Aliucord is not installed (only the Manager)"
        echo "  • Safe mode is enabled"
        echo "  • logcat buffer was not accessible"
        echo ""
        info "Try running: ./aliucord-test.sh --logcat-only"
        info "Or wait a few more seconds and try again"
    else
        echo "$log_output"
        echo ""

        # ── Analyze results ──
        echo -e "${BOLD}── Analysis ──${NC}"

        # Check if our plugin loaded
        if echo "$log_output" | grep -qi "Loading plugin:.*${plugin_name}"; then
            ok "✓ Plugin '${plugin_name}' was LOADED"
        else
            warn "✗ No 'Loading plugin: ${plugin_name}' entry found"
        fi

        # Check if our plugin started
        if echo "$log_output" | grep -qi "Started plugin:.*${plugin_name}"; then
            ok "✓ Plugin '${plugin_name}' was STARTED successfully"
            local start_time
            start_time=$(echo "$log_output" | grep -i "Started plugin:.*${plugin_name}" | grep -oP 'in \K\d+' | head -1)
            [ -n "$start_time" ] && info "  Startup time: ${start_time}ms"
        else
            warn "✗ No 'Started plugin: ${plugin_name}' entry found"
        fi

        # Check for failures
        if echo "$log_output" | grep -qi "Failed to load.*${plugin_name}\|failed.*${plugin_name}"; then
            fail "✗ Plugin '${plugin_name}' FAILED to load!"
            echo "$log_output" | grep -i "fail" | sed 's/^/  /'
        fi

        # Check for any errors at all
        local error_count
        error_count=$(echo "$log_output" | grep -ci "error\|exception\|failed" || true)
        if [ "$error_count" -gt 0 ]; then
            warn "$error_count error/exception line(s) in log — review above"
        fi
    fi

    # ── Step 5: Check for new crashes ──
    echo ""
    echo -e "${BOLD}── Crash Check ──${NC}"
    sleep 2

    if [ -d "$CRASHLOGS_DIR" ]; then
        local newest_crash
        newest_crash=$(find "$CRASHLOGS_DIR" -maxdepth 1 -name "*.txt" -type f -newer "$dest" 2>/dev/null | head -1)
        if [ -n "$newest_crash" ]; then
            fail "⚠ NEW CRASH detected after plugin deploy!"
            echo -e "  Crash log: ${YELLOW}$(basename "$newest_crash")${NC}"
            echo ""
            head -20 "$newest_crash"
        else
            ok "No new crash logs since deploy"
        fi
    else
        ok "No crashlogs directory — no crashes"
    fi

    echo ""
    echo -e "${BOLD}════════════════════════════════${NC}"
    info "Full raw log: logcat -d | grep -i aliucord"
    info "Plugin location: $dest"
}

# ── Command: undeploy ──
cmd_undeploy() {
    local plugin_name="$1"
    local dest="${PLUGINS_DIR}/${plugin_name}.zip"

    if [ ! -f "$dest" ]; then
        # Try with .zip already appended
        dest="${PLUGINS_DIR}/${plugin_name}"
        if [ ! -f "$dest" ]; then
            fail "Plugin not found: $plugin_name"
            return 1
        fi
    fi

    info "Removing: $dest"
    rm -f "$dest"
    ok "Plugin removed"

    if [ -f "${dest}.bak" ]; then
        info "Restoring backup: ${dest}.bak → $dest"
        mv "${dest}.bak" "$dest"
        ok "Backup restored"
    fi

    info "Force-restarting Discord..."
    am force-stop "$DISCORD_PKG" 2>/dev/null
    sleep 1
    monkey -p "$DISCORD_PKG" -c android.intent.category.LAUNCHER 1 2>/dev/null >/dev/null
    ok "Discord restart triggered"
}

# ── Main ──
usage() {
    echo "Aliucord Plugin Tester"
    echo ""
    echo "Usage:"
    echo "  $0 <plugin.zip>          Deploy and test a plugin"
    echo "  $0 --status              List installed plugins & config"
    echo "  $0 --logcat-only         Read current Aliucord log entries"
    echo "  $0 --crash-check         Show latest crash logs"
    echo "  $0 --undeploy <name>     Remove a plugin and restart Discord"
    echo "  $0 --help                Show this help"
}

main() {
    check_prereqs || exit 1

    case "${1:-}" in
        --status)
            cmd_status
            ;;
        --logcat-only|--logcat)
            cmd_logcat
            ;;
        --crash-check|--crashes)
            cmd_crash_check
            ;;
        --undeploy|--remove)
            [ -z "${2:-}" ] && { fail "Specify plugin name"; exit 1; }
            cmd_undeploy "$2"
            ;;
        --help|-h|"")
            usage
            ;;
        *)
            cmd_test "$1"
            ;;
    esac
}

main "$@"
