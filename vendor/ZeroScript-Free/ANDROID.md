# Running ZeroScript on an Android phone (no PC)

ZeroScript has no cloud mode. The extension only ever connects to
`ws://127.0.0.1:<port>` (hardcoded in `background.js`; the manifest only grants
`127.0.0.1` host permissions), so **the bridge and the browser must run on the
same device**. On Android that is possible: Termux runs the Python bridge, and a
Chromium browser with extension support runs the extension. Both are on the
phone, so `127.0.0.1` resolves between them.

## Read this first: what will and will not work

| | Works on Android? |
| --- | --- |
| The bridge (`bridge.py`) | **Yes** — pure Python, one dependency (`websockets`). |
| The extension | **Yes**, in a Chromium browser that loads extensions. |
| A **generic** MCP target | **Yes** — this is the supported path. |
| A **Roblox Studio** target | **No.** Roblox Studio is Windows/macOS only; there is no Android build, and the Roblox path shells out to Windows `tasklist`/`taskkill`. |

So on a phone you must use a **generic target** (see `TARGETS.md`). The
target-profile layer in this vendored copy is what makes that possible; upstream
ZeroScript is Roblox-only and cannot do this. All the Windows-only supervision
is gated behind `kind: "roblox"`, so a generic target never calls it.

You also need an MCP server that itself runs on Android. Anything pure-Python or
pure-Node that Termux can run is fine (a filesystem server, a notes/database
server, your own script). Desktop apps like Blender are not.

## 1. Install Termux

Get Termux from **F-Droid** or its GitHub releases — *not* the Play Store
version, which is obsolete and unmaintained.

```bash
pkg update && pkg upgrade -y
pkg install python git -y
```

Do **not** run `pip install --upgrade pip` in Termux; it breaks the packaged pip.
Use `pkg install python-pip` if pip needs updating.

## 2. Get the bridge and its dependency

```bash
cd ~
git clone https://github.com/hipliteidk-glitch/potential-waddle
cd potential-waddle/vendor/ZeroScript-Free
pip install websockets
```

## 3. Point it at a non-Roblox target

Replace `config.json` with a generic profile. Example using a filesystem MCP
server over a folder on the phone:

```json
{
  "target": {
    "id": "files",
    "kind": "generic",
    "name": "my phone files",
    "short": "Files",
    "offline_hint": "Check the MCP server command is installed in Termux."
  },
  "mcpServers": {
    "files": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/data/data/com.termux/files/home/notes"]
    }
  }
}
```

That one needs Node: `pkg install nodejs -y`. Any MCP server Termux can execute
works — see `config.examples.json`.

Start it:

```bash
python bridge.py
```

You want a green `ready N tools available - <your target> connected`. Leave this
Termux session running. Run `termux-wake-lock` (or enable Termux's wake lock
from its notification) so Android doesn't suspend the process when the screen
turns off.

## 4. Install the extension in a browser that supports them

**Kiwi Browser is dead** — discontinued and removed from the Play Store in
January 2025. Do not follow older guides that recommend it. Current options:

- **Microsoft Edge Canary** — inherited Kiwi's extension code. Settings > About,
  tap the build number 5 times to unlock Developer Options, then use
  "Extension install by id" or load an unpacked/CRX extension.
- **Quetta** or **Lemur** — Chromium browsers on the Play Store that support
  Chrome Web Store and Edge add-ons, and can sideload a local CRX/ZIP.

ZeroScript is unpacked and unsigned, so you need a browser that accepts a local
folder or a ZIP/CRX you build from `zeroscript-extension/`. Load it, then open
one of the supported AI chat sites (DeepSeek is the most reliable).

## 5. Use it

The status dot should go green and the button should read **▶ Start Files
agent** (or whatever your target's `short` name is). If it says the bridge is
offline, the Termux process died or was suspended by Android's battery
optimisation — re-check step 3 and the wake lock.

## Honest caveats

- This is a **fiddly, unsupported setup**. Upstream tests on Windows/macOS
  desktops; nobody tests Android.
- Android aggressively kills background processes. Expect the bridge to drop
  unless you hold a wake lock and exempt Termux from battery optimisation.
- Mobile Chromium extension support is second-class; MV3 service workers can be
  unreliable on these builds.
- Screen-real-estate: the ZeroScript status bar sits above the chat composer and
  is cramped on a phone.
- **If your goal was Roblox specifically, this does not get you there.** No
  amount of phone setup gives you Roblox Studio.
