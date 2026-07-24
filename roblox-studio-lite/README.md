# Roblox Studio Lite

A self-contained in-game building experience for Roblox: top toolbar, toolbox, properties panel, explorer, grid snapping, secure server-owned edits, and DataStore save/load.

## Files

```text
roblox-studio-lite/
└── src/
    ├── ServerScriptService/
    │   └── StudioLiteServer.server.lua
    └── StarterPlayerScripts/
        └── StudioLiteClient.client.lua
```

## Install in Roblox Studio

1. Open your place in Roblox Studio.
2. In **Explorer**, create/paste:
   - A **Script** in `ServerScriptService` named `StudioLiteServer`, then paste `src/ServerScriptService/StudioLiteServer.server.lua`.
   - A **LocalScript** in `StarterPlayer > StarterPlayerScripts` named `StudioLiteClient`, then paste `src/StarterPlayerScripts/StudioLiteClient.client.lua`.
3. Press **Play**. The server script automatically creates:
   - `ReplicatedStorage.StudioLiteRemotes`
   - `Workspace.StudioLiteBuilds`
4. For save/load in Studio tests, enable **Game Settings > Security > Enable Studio Access to API Services** and publish the place.

No API keys are required. All persistence uses Roblox `DataStoreService` from the server.

## Included UI

- **Toolbar**: Select, Move, Scale, Rotate, Save, Load, Clear, Grid toggle.
- **Toolbox**: Brick, Sphere, Wedge, Cylinder.
- **Properties**: name, position, size, hex color, material, apply, delete.
- **Explorer**: lists the current player's created objects and selects them on click.
- **Grid**: local visual grid with X/Z snap while moving.

## Controls

| Input | Action |
| --- | --- |
| `1` | Select tool |
| `2` | Move tool |
| `3` | Scale tool |
| `4` | Rotate tool |
| Drag with Move selected | Move selected part on X/Z grid |
| Drag with Scale selected | Uniformly scale selected part |
| Drag with Rotate selected | Rotate selected part in 15° increments |
| `Q` / `E` | Rotate selected part -15° / +15° |
| `Delete` / `Backspace` | Delete selected part |
| `G` | Toggle grid |
| `Ctrl+S` | Save build |
| `Ctrl+L` | Load build |

## Security model

The client only requests actions. The server validates ownership, part type, size, position, material, part count, and save/load cooldowns before changing replicated objects or DataStores.

Limits are defined near the top of `StudioLiteServer.server.lua`:

- `MAX_PARTS_PER_PLAYER = 300`
- `MAX_POSITION = 2048`
- `MIN_SIZE = 0.25`
- `MAX_SIZE = 128`
- save/load cooldowns

## Notes and next upgrades

- Current build folders are per player: `Workspace.StudioLiteBuilds/<UserId>`.
- Client-created grid parts are local-only and non-queryable, so they do not replicate or block selection.
- Add collaboration by changing the ownership checks and folder structure on the server.
- Add copy/paste or undo/redo by storing action history in the LocalScript and replaying validated server requests.
