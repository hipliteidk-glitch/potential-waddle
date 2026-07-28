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

## Games

- [`games/wellspring.html`](games/wellspring.html) — **WELLSPRING**, a single-file
  arcade game about flying a ship you cannot steer by bending the gravity around
  it. No build step or dependencies; just open the file. See
  [`games/README.md`](games/README.md).

## Deploying

The game is one self-contained HTML file with no build step, so it deploys to
any static host.

### GitHub Pages

The ready-made workflow lives at `deploy/github-pages-workflow.yml`. It is not
installed automatically because the CI token here is not permitted to create
workflow files. To enable it:

```bash
mkdir -p .github/workflows
cp deploy/github-pages-workflow.yml .github/workflows/deploy-pages.yml
git add .github/workflows/deploy-pages.yml
git commit -m "Enable Pages deploy" && git push
```

Then, once: **Settings → Pages → Build and deployment → Source → GitHub
Actions**. The site publishes on each push to `main`, or on demand from the
Actions tab.

Pages on a **private** repo requires a paid GitHub plan. This repo is
currently private, so either make it public or use one of the options below.

### Anywhere else

Nothing needs building, so any of these work as-is:

- Drag the repo folder onto [Netlify Drop](https://app.netlify.com/drop)
- `npx vercel --prod`
- Just open `games/wellspring.html` from disk — it needs no server at all

Locally: `python3 -m http.server` then visit
<http://localhost:8000/games/wellspring.html>.
