#!/usr/bin/env python3
"""anti_ai_img.py — Anti-AI image tool.

Two things it can do:

  1. protect  — take one of YOUR images and make it hostile to AI scraping:
                * adds a subtle adversarial-style noise cloak (structured
                  high-frequency perturbation that is hard for humans to see
                  but degrades the image as clean training data)
                * optionally tiles a visible "NO AI TRAINING" watermark
                * strips original metadata (EXIF/GPS) and embeds a machine-
                  readable "noai / noimageai" opt-out (XMP + text chunks),
                  the same directive DeviantArt/Cara-style crawlers honour

  2. poster   — generate a ready-to-post "NO AI" protest poster/badge
                from scratch (no input image needed).

Honesty note: the noise cloak is a best-effort deterrent in the spirit of
Glaze/Nightshade, not a mathematical guarantee. Combine it with the metadata
opt-out and the visible watermark for the strongest effect.

Usage:
    python anti_ai_img.py protect photo.jpg                    # cloak + metadata
    python anti_ai_img.py protect photo.jpg -o safe.png -w     # + visible watermark
    python anti_ai_img.py protect photo.jpg --strength 8       # stronger cloak
    python anti_ai_img.py poster                               # make no_ai_poster.png
    python anti_ai_img.py poster --text "HUMAN ART ONLY" --size 1600

Requires: Pillow, numpy
"""

from __future__ import annotations

import argparse
import io
import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from PIL.PngImagePlugin import PngInfo

# --------------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------------

XMP_TEMPLATE = """<?xpacket begin="\ufeff" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:xmpRights="http://ns.adobe.com/xap/1.0/rights/"
    xmlns:plus="http://ns.useplus.org/ldf/xmp/1.0/">
   <xmpRights:Marked>True</xmpRights:Marked>
   <xmpRights:UsageTerms>
    <rdf:Alt><rdf:li xml:lang="x-default">noai, noimageai. AI/ML training, scraping, indexing for generative models, and dataset inclusion are expressly prohibited.</rdf:li></rdf:Alt>
   </xmpRights:UsageTerms>
   <plus:DataMining>http://ns.useplus.org/ldf/vocab/DMI-PROHIBITED-AIMLTRAINING</plus:DataMining>
   <dc:rights>
    <rdf:Alt><rdf:li xml:lang="x-default">noai, noimageai</rdf:li></rdf:Alt>
   </dc:rights>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>"""


def load_font(size: int) -> ImageFont.FreeTypeFont:
    """Best-effort bold font lookup with graceful fallback."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "DejaVuSans-Bold.ttf",
        "arialbd.ttf",
        "Arial Bold.ttf",
    ]
    for name in candidates:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _png_metadata() -> PngInfo:
    meta = PngInfo()
    meta.add_text("noai", "true")
    meta.add_text("noimageai", "true")
    meta.add_text("Copyright", "noai, noimageai — AI/ML training prohibited")
    meta.add_itxt("XML:com.adobe.xmp", XMP_TEMPLATE, zip=False)
    return meta


def _inject_jpeg_xmp(jpeg_bytes: bytes) -> bytes:
    """Insert an XMP APP1 segment right after SOI in a JPEG byte stream."""
    if not jpeg_bytes.startswith(b"\xff\xd8"):
        return jpeg_bytes
    payload = b"http://ns.adobe.com/xap/1.0/\x00" + XMP_TEMPLATE.encode("utf-8")
    segment = b"\xff\xe1" + struct.pack(">H", len(payload) + 2) + payload
    return jpeg_bytes[:2] + segment + jpeg_bytes[2:]


def save_with_optout(img: Image.Image, out_path: Path, quality: int = 95) -> None:
    """Save image with original metadata stripped and no-AI opt-out embedded."""
    suffix = out_path.suffix.lower()
    if suffix in {".jpg", ".jpeg"}:
        buf = io.BytesIO()
        img.convert("RGB").save(buf, "JPEG", quality=quality, subsampling=1)
        out_path.write_bytes(_inject_jpeg_xmp(buf.getvalue()))
    elif suffix == ".png":
        img.save(out_path, "PNG", pnginfo=_png_metadata())
    elif suffix == ".webp":
        img.save(out_path, "WEBP", quality=quality, xmp=XMP_TEMPLATE.encode("utf-8"))
    else:
        img.save(out_path)
        print(f"  ! {suffix} does not support the no-AI metadata block; "
              f"saved without it (use .png/.jpg/.webp).")


# --------------------------------------------------------------------------
# protect — cloak an existing image
# --------------------------------------------------------------------------

def cloak(img: Image.Image, strength: float, seed: int) -> Image.Image:
    """Apply a structured high-frequency perturbation ("cloak").

    Mixes three layers, all scaled by `strength` (in 8-bit levels):
      * per-pixel Gaussian noise (defeats naive de-duplication / hashing)
      * chroma-shifted sinusoidal interference pattern (targets the
        downsampling + patch statistics vision models rely on)
      * blurred blotch field, applied in opposite directions on the
        red/blue channels (low-visibility feature drift)
    """
    rng = np.random.default_rng(seed)
    arr = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = arr.shape

    # 1. Fine Gaussian grain
    grain = rng.normal(0.0, strength * 0.45, size=(h, w, 3))

    # 2. Sinusoidal interference, different phase per channel
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    pattern = np.zeros((h, w, 3), dtype=np.float32)
    for c in range(3):
        fx, fy = rng.uniform(0.25, 0.75, 2)          # cycles per pixel-ish
        phase = rng.uniform(0, 2 * math.pi)
        angle = rng.uniform(0, math.pi)
        u = xx * math.cos(angle) + yy * math.sin(angle)
        v = -xx * math.sin(angle) + yy * math.cos(angle)
        pattern[:, :, c] = np.sin(u * fx * 2 * math.pi + phase) * \
                           np.cos(v * fy * 2 * math.pi)
    pattern *= strength * 0.6

    # 3. Smooth blotch field pushing R and B channels apart
    blotch_small = rng.normal(0.0, 1.0, size=(max(h // 24, 1), max(w // 24, 1)))
    blotch_img = Image.fromarray(
        ((blotch_small - blotch_small.min()) /
         (np.ptp(blotch_small) + 1e-6) * 255).astype(np.uint8)
    ).resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(6))
    blotch = (np.asarray(blotch_img).astype(np.float32) / 255.0 - 0.5) * strength * 1.2
    drift = np.zeros((h, w, 3), dtype=np.float32)
    drift[:, :, 0] = blotch          # red up where blotch is bright
    drift[:, :, 2] = -blotch         # blue down — hue drift, low visibility

    out = np.clip(arr + grain + pattern + drift, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


def add_watermark(img: Image.Image, text: str, opacity: int) -> Image.Image:
    """Tile a diagonal repeating watermark across the image."""
    base = img.convert("RGBA")
    w, h = base.size
    layer = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    font = load_font(max(w // 18, 24))
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    step_x, step_y = int(tw * 1.5), int(th * 4)
    for row, y in enumerate(range(0, h * 2, step_y)):
        offset = (row % 2) * step_x // 2
        for x in range(-step_x, w * 2, step_x):
            draw.text((x + offset, y), text, font=font,
                      fill=(255, 255, 255, opacity),
                      stroke_width=2, stroke_fill=(0, 0, 0, opacity // 2))
    layer = layer.rotate(30, resample=Image.BICUBIC)
    left, top = (layer.width - w) // 2, (layer.height - h) // 2
    layer = layer.crop((left, top, left + w, top + h))
    return Image.alpha_composite(base, layer).convert("RGB")


def cmd_protect(args: argparse.Namespace) -> None:
    src = Path(args.image)
    if not src.exists():
        sys.exit(f"error: {src} not found")
    out = Path(args.output) if args.output else src.with_name(
        f"{src.stem}_noai{src.suffix if src.suffix.lower() in {'.jpg', '.jpeg', '.png', '.webp'} else '.png'}")

    img = Image.open(src).convert("RGB")
    print(f"* loaded {src} ({img.width}x{img.height})")

    print(f"* applying noise cloak (strength {args.strength}, seed {args.seed})")
    img = cloak(img, strength=args.strength, seed=args.seed)

    if args.watermark:
        print(f"* tiling visible watermark: {args.watermark_text!r}")
        img = add_watermark(img, args.watermark_text, opacity=args.watermark_opacity)

    save_with_optout(img, out, quality=args.quality)
    print(f"* stripped original metadata, embedded noai/noimageai opt-out")
    print(f"-> wrote {out}")


# --------------------------------------------------------------------------
# poster — generate an anti-AI poster from scratch
# --------------------------------------------------------------------------

def cmd_poster(args: argparse.Namespace) -> None:
    s = args.size
    bg, ink, red = (238, 232, 220), (24, 22, 20), (198, 32, 32)
    img = Image.new("RGB", (s, s), bg)
    draw = ImageDraw.Draw(img)

    # grungy paper speckle
    rng = np.random.default_rng(7)
    speck = rng.integers(0, 255, size=(s, s), dtype=np.uint8)
    speck_img = Image.fromarray(speck).filter(ImageFilter.GaussianBlur(1))
    img = Image.composite(Image.new("RGB", (s, s), (200, 192, 178)), img,
                          speck_img.point(lambda p: 255 if p > 247 else 0))
    draw = ImageDraw.Draw(img)

    # headline / footer (auto-shrunk to fit the frame width)
    def fit_font(text: str, start_px: int, max_w: int) -> ImageFont.FreeTypeFont:
        size = start_px
        while size > 10:
            font = load_font(size)
            bbox = draw.textbbox((0, 0), text, font=font)
            if bbox[2] - bbox[0] <= max_w:
                return font
            size = int(size * 0.93)
        return load_font(size)

    max_w = int(s * 0.86)
    for text, y, fill, start in (
        (args.text, int(s * 0.06), ink, int(s * 0.135)),
        (args.subtext, int(s * 0.86), red, int(s * 0.055)),
    ):
        font = fit_font(text, start, max_w)
        bbox = draw.textbbox((0, 0), text, font=font)
        tw = bbox[2] - bbox[0]
        draw.text(((s - tw) / 2 - bbox[0], y), text, font=font, fill=fill)

    # central "AI" glyph with prohibition circle-slash
    cx, cy, r = s // 2, int(s * 0.5), int(s * 0.24)
    ai_font = load_font(int(s * 0.26))
    bbox = draw.textbbox((0, 0), "AI", font=ai_font)
    draw.text((cx - (bbox[2] - bbox[0]) / 2 - bbox[0],
               cy - (bbox[3] - bbox[1]) / 2 - bbox[1]),
              "AI", font=ai_font, fill=ink)
    ring_w = max(int(s * 0.028), 6)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=red, width=ring_w)
    off = r / math.sqrt(2) - ring_w * 0.35
    draw.line([cx - off, cy - off, cx + off, cy + off], fill=red, width=ring_w)

    # rough border
    m = int(s * 0.025)
    draw.rectangle([m, m, s - m, s - m], outline=ink, width=max(int(s * 0.006), 3))

    # slight print-imperfection grain
    arr = np.asarray(img).astype(np.int16)
    arr += rng.integers(-6, 7, size=arr.shape, dtype=np.int16)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))

    out = Path(args.output)
    save_with_optout(img, out)
    print(f"-> wrote {out} ({s}x{s}) with noai metadata embedded")


# --------------------------------------------------------------------------

def main() -> None:
    p = argparse.ArgumentParser(description="Anti-AI image tool: cloak your images against AI training, or generate NO-AI posters.")
    sub = p.add_subparsers(dest="cmd", required=True)

    pr = sub.add_parser("protect", help="cloak an existing image + embed no-AI metadata")
    pr.add_argument("image", help="input image path")
    pr.add_argument("-o", "--output", help="output path (default: <name>_noai.<ext>)")
    pr.add_argument("-s", "--strength", type=float, default=5.0,
                    help="cloak strength in 8-bit levels, 2=subtle 10=aggressive (default 5)")
    pr.add_argument("--seed", type=int, default=1337, help="noise seed (default 1337)")
    pr.add_argument("-w", "--watermark", action="store_true",
                    help="also tile a visible watermark across the image")
    pr.add_argument("--watermark-text", default="NO AI TRAINING")
    pr.add_argument("--watermark-opacity", type=int, default=60,
                    help="watermark alpha 0-255 (default 60)")
    pr.add_argument("-q", "--quality", type=int, default=95, help="JPEG/WebP quality")
    pr.set_defaults(func=cmd_protect)

    po = sub.add_parser("poster", help="generate a NO-AI poster/badge from scratch")
    po.add_argument("-o", "--output", default="no_ai_poster.png")
    po.add_argument("--size", type=int, default=1080, help="square size in px (default 1080)")
    po.add_argument("--text", default="SAY NO TO AI", help="headline text")
    po.add_argument("--subtext", default="HUMAN MADE ONLY", help="footer text")
    po.set_defaults(func=cmd_poster)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
