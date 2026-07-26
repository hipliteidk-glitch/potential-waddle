# Doraemon recap generator

Downloaded/reconstructed from the supplied `BiLTM.txtmm` paste as a runnable Python script.

## Prerequisites

- Python 3.9+
- FFmpeg available on `PATH`
- An internet connection while gTTS generates the narration

## Install and render

```bash
python -m venv .venv
. .venv/bin/activate              # Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
python doraemon_recap_generator.py --output doraemon_834ab_recap.mp4
```

Optional background music:

```bash
python doraemon_recap_generator.py --bgm bgm.mp3
```

Intermediate narration and slides are written to `recap_assets/`; rendered media is intentionally ignored by Git.

## Vendored: ZeroScript-Free

`vendor/ZeroScript-Free/` contains a checked-in copy of
[sebattfg/ZeroScript-Free](https://github.com/sebattfg/ZeroScript-Free) — a free
browser extension plus local Python bridge that turns a chat AI (DeepSeek,
Gemini, Kimi, GLM, Qwen, Arena, Meta AI) into a Roblox Studio agent via Studio's
built-in MCP server. It is licensed GPL-3.0; see
`vendor/ZeroScript-Free/LICENSE` and `vendor/ZeroScript-Free/VENDOR.md` (upstream
commit and re-sync instructions).

This copy is **no longer Roblox-only**: a `target` profile in
`vendor/ZeroScript-Free/config.json` lets the same bridge and extension drive any
MCP server (Blender, a filesystem server, your own). Roblox is just the default
profile, and its behaviour is unchanged — the system prompt it sends is
byte-for-byte identical to upstream. See `vendor/ZeroScript-Free/TARGETS.md` for
the setup, `config.examples.json` for ready-to-copy profiles, and
`zeroscript-extension/test-target.js` for the regression tests.
