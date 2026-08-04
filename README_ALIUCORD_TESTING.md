# Aliucord Plugin Testing from Termux

This repo contains tools to inspect and verify Aliucord plugin loading directly from Termux, **without root access**.

## The Problem

Aliucord does not expose a debug interface, local socket, or log file that Termux can read. The only ways to verify plugin loading are:

1. **Open Discord manually** and check the plugins list in settings
2. **Read logcat** (works from Termux with `android-tools`)
3. **Install a DebugBridge plugin** that writes registry state to a readable file + runs a local HTTP server

This repo provides **all three approaches**.

---

## Files

| File | Purpose |
|------|---------|
| `aliucord-test.sh` | Full deploy → restart → logcat → analyze pipeline |
| `ac-query.sh` | Query the DebugBridge HTTP server for live plugin state |
| `aliucord-debug-bridge/` | Source for the DebugBridge Aliucord plugin |

---

## Approach 1: Logcat Testing (No extra plugin needed)

### Prerequisites

```bash
termux-setup-storage      # Grant storage access
pkg install android-tools # For logcat, am, monkey commands
```

### Usage

```bash
# Full test: deploy plugin, restart Discord, read logs, check crashes
chmod +x aliucord-test.sh
./aliucord-test.sh MyPlugin.zip

# Just see current Aliucord logs
./aliucord-test.sh --logcat-only

# List installed plugins
./aliucord-test.sh --status

# Check crash logs
./aliucord-test.sh --crash-check

# Remove a plugin
./aliucord-test.sh --undeploy MyPlugin
```

### What it does

1. Validates the plugin zip has `manifest.json`
2. Copies to `/sdcard/Aliucord/plugins/`
3. Clears logcat buffer
4. Force-stops and relaunches Discord
5. Waits 8 seconds for initialization
6. Greps logcat for `[PluginManager]` entries
7. Analyzes output for load/start/fail messages about your plugin
8. Checks for new crash logs

### Key logcat messages to look for

```
[PluginManager] Loading plugin: MyPlugin         ← Plugin found and being loaded
[PluginManager] Started plugin: MyPlugin in 42ms ← Plugin started successfully
[PluginManager] Failed to load plugin MyPlugin   ← Something went wrong
[Aliucord] Safe mode is enabled. skipping...      ← External plugins disabled
```

---

## Approach 2: DebugBridge Plugin (Full registry access)

This is the most powerful approach. Install the `DebugBridge` plugin into Aliucord once, and then you can query the **exact internal state** of the plugin registry from Termux at any time — without restarting Discord.

### What DebugBridge does

- **On start**: Dumps the full plugin registry to `/sdcard/Aliucord/debug/plugin_registry.json`
- **HTTP server**: Listens on `127.0.0.1:2273` (localhost only, not network-accessible)
  - `GET /status` → Full JSON registry (refreshes on each request)
  - `GET /plugins` → Plain text list of plugin names + enabled state
  - `GET /health` → Simple health check

### Build & install

Build the plugin using the [Aliucord plugin template](https://github.com/Aliucord/plugins-template) or your existing Gradle setup. Then deploy:

```bash
cp DebugBridge.zip /sdcard/Aliucord/plugins/
# Restart Discord once to activate it
am force-stop com.discord
monkey -p com.discord -c android.intent.category.LAUNCHER 1
```

### Query from Termux

```bash
chmod +x ac-query.sh

# Full status (pretty-printed JSON)
./ac-query.sh

# List all plugins
./ac-query.sh plugins

# Is the server alive?
./ac-query.sh health

# Check a specific plugin
./ac-query.sh check MyPlugin
```

### Or with curl directly

```bash
# Quick check
curl localhost:2273/health

# Full JSON
curl localhost:2273/status | python3 -m json.tool

# Just names
curl localhost:2273/plugins
```

### Or read the file directly

```bash
cat /sdcard/Aliucord/debug/plugin_registry.json | python3 -m json.tool
```

### Sample output

```json
{
  "environment": {
    "timestamp": 1722793200000,
    "discordVersion": 267013,
    "basePath": "/storage/emulated/0/Aliucord",
    "safeMode": false,
    "androidVersion": "14",
    "sdkInt": 34
  },
  "loadedPlugins": [
    {
      "name": "MyPlugin",
      "enabled": true,
      "version": "1.0.0",
      "filename": "MyPlugin",
      "isCorePlugin": false
    },
    {
      "name": "DebugBridge",
      "enabled": true,
      "version": "1.0.0",
      "filename": "DebugBridge",
      "isCorePlugin": false
    }
  ],
  "loadedCount": 2,
  "failedPlugins": [],
  "failedCount": 0,
  "summary": "2 Installed (0 core) | 2 Enabled (0 core)"
}
```

---

## Approach 3: Manual Check (no tools)

If you just want to verify a plugin without any scripts:

1. Copy your `.zip` to `/sdcard/Aliucord/plugins/`
2. Open Discord
3. Go to **User Settings → Plugins**
4. Your plugin should appear in the list

---

## Troubleshooting

### "Storage not accessible"
Run `termux-setup-storage` and grant the permission prompt.

### "No Aliucord log entries in logcat"
- Discord may not have started yet — wait longer
- The logcat buffer may have rotated — run the test again
- Check if Safe Mode is enabled: `./aliucord-test.sh --status`

### "Plugin loads but doesn't appear in settings"
- Ensure `manifest.json` has correct `pluginClassName` matching your main class
- Ensure the class extends `com.aliucord.entities.Plugin`
- Check logcat for `Failed to load` errors

### "DebugBridge HTTP server not responding"
- Ensure Discord is running (DebugBridge only runs inside Discord)
- Port 2273 may be taken — check `netstat -tlnp | grep 2273`
- Try reading the file directly: `cat /sdcard/Aliucord/debug/plugin_registry.json`

### "Some plugins failed to load"
- Run `./aliucord-test.sh --logcat-only` to see error details
- Common causes: wrong Kotlin version, missing dependencies, incompatible Discord version

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  Android Device                                               │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Discord (Aliucord-patched)                             │ │
│  │                                                         │ │
│  │  PluginManager.plugins ──→ Logger ──→ logcat            │ │
│  │        │                        └──→ AppLog             │ │
│  │        │                                                │ │
│  │        └──→ DebugBridge Plugin                          │ │
│  │                   │                                     │ │
│  │                   ├──→ /sdcard/Aliucord/debug/          │ │
│  │                   │    plugin_registry.json             │ │
│  │                   │                                     │ │
│  │                   └──→ HTTP 127.0.0.1:2273              │ │
│  └─────────────────────────────────────────────────────────┘ │
│          │                     │                              │
│          │ /sdcard/Aliucord/   │ logcat                      │
│          ▼                     ▼                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Termux                                                  │ │
│  │                                                         │ │
│  │  aliucord-test.sh    → deploy + logcat + crash check    │ │
│  │  ac-query.sh         → curl localhost:2273/status       │ │
│  │  cat ...registry.json → read file directly              │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```
