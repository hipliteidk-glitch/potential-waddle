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

## Roblox Studio Lite package

This repository also includes a Roblox in-game builder package under [`roblox-studio-lite/`](roblox-studio-lite/). It contains a secure server script plus a client GUI script for a lightweight Studio-like building experience inside Roblox.
