#!/usr/bin/env python3
"""Create a vertical recap video from the storyboard in BiLTM.txtmm.

Requires: moviepy==1.0.3, gTTS, Pillow, and an ffmpeg installation.
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path
from typing import Dict, Iterable, List

from gtts import gTTS
from moviepy.editor import (
    AudioFileClip,
    CompositeAudioClip,
    CompositeVideoClip,
    ImageClip,
    TextClip,
    VideoFileClip,
    concatenate_videoclips,
    vfx,
)
from PIL import Image, ImageDraw, ImageFont

CONFIG = {"video_width": 1080, "video_height": 1920, "fps": 24}

STORY1_BEATS = [
    {"name": "HOOK", "duration": 3, "narration": "Nobita wanted to make games... but reality became the game.", "visual": "Nobita with game controller, dramatic lighting", "tone": "Dark", "emoji": "🎮"},
    {"name": "SETUP", "duration": 9, "narration": "Nobita dreamed of becoming a game creator. But when he showed off his homemade game, Suneo and Doraemon laughed. His skills? Trash. His ideas? Nonsense.", "visual": "Nobita holding game cartridge, friends laughing", "tone": "Sad", "emoji": "😢"},
    {"name": "INCITING INCIDENT", "duration": 8, "narration": "Until Doraemon dropped the Game Book gadget. Anything Nobita wrote became reality. His boring life? Turned into a video game instantly.", "visual": "Doraemon with glowing Game Book", "tone": "Excited", "emoji": "✨"},
    {"name": "ESCALATION", "duration": 15, "narration": "Mom became a boss fight. Ditches became death traps. Homework? A final level he couldn't escape. Then Gian and Suneo joined with sub-controllers. Suneo created an RPG with diamond hammers and platinum swords. Chaos exploded.", "visual": "Nobita running from game enemies, Suneo with RPG gear", "tone": "Chaotic", "emoji": "⚔️"},
    {"name": "CLIMAX", "duration": 7, "narration": "The battles got so ridiculous... the game crashed. Nobita's dream became a nightmare.", "visual": "Game over screen, Nobita shocked", "tone": "Tense", "emoji": "💥"},
    {"name": "RESOLUTION", "duration": 3, "narration": "Lesson learned? Be careful what you wish for.", "visual": "Nobita thinking, subtle smile", "tone": "Reflective", "emoji": "🤔"},
]
STORY2_BEATS = [
    {"name": "TRANSITION HOOK", "duration": 3, "narration": "But that wasn't Nobita's only disaster...", "visual": "Halloween pumpkin glowing", "tone": "Mysterious", "emoji": "🎃"},
    {"name": "SETUP", "duration": 7, "narration": "Halloween night. Nobita found special pumpkin seeds. Gene-editing tool in hand, he created glowing jack-o'-lanterns. Beautiful? Yes. Dangerous? Absolutely.", "visual": "Nobita with glowing seeds, gene tool", "tone": "Excited", "emoji": "🧬"},
    {"name": "ESCALATION", "duration": 10, "narration": "He tossed a weird-shaped pumpkin in the yard. His mom cooked it into dinner. But these weren't normal pumpkins. They were alive. And they wanted revenge.", "visual": "Mom cooking pumpkins, pumpkins with angry faces", "tone": "Humorous", "emoji": "😱"},
    {"name": "CLIMAX", "duration": 15, "narration": "The discarded pumpkins came to life. They marched through town chanting. An army of glowing gourds on the loose. Nobita panicked. Everyone panicked.", "visual": "Army of marching pumpkins, town chaos", "tone": "Chaotic", "emoji": "👻"},
    {"name": "RESOLUTION", "duration": 8, "narration": "But the pumpkins didn't want destruction. They wanted to be eaten. The night ended in a massive pumpkin feast. Halloween saved... by hungry vegetables.", "visual": "Pumpkin feast, everyone happy", "tone": "Heartwarming", "emoji": "🍽️"},
    {"name": "FINAL CLIFFHANGER", "duration": 2, "narration": "What would Nobita ruin next?", "visual": "Nobita thinking about next adventure", "tone": "Mysterious", "emoji": "🤷"},
]
COLORS = {"Dark": (20, 20, 40), "Sad": (30, 30, 70), "Excited": (80, 40, 120), "Chaotic": (140, 30, 30), "Tense": (60, 20, 60), "Reflective": (30, 30, 80), "Mysterious": (10, 10, 30), "Humorous": (120, 80, 40), "Heartwarming": (80, 40, 60)}


def font(size: int):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "arial.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def wrap(draw: ImageDraw.ImageDraw, text: str, use_font, width: int) -> List[str]:
    lines, current = [], []
    for word in text.split():
        candidate = " ".join(current + [word])
        if current and draw.textbbox((0, 0), candidate, font=use_font)[2] > width:
            lines.append(" ".join(current)); current = [word]
        else:
            current.append(word)
    return lines + ([" ".join(current)] if current else [])


def slides(beats: List[Dict[str, object]], label: str, directory: Path) -> List[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    paths = []
    title_font, text_font, small_font = font(66), font(46), font(32)
    for index, beat in enumerate(beats, start=1):
        image = Image.new("RGB", (CONFIG["video_width"], CONFIG["video_height"]), COLORS[beat["tone"]])
        draw = ImageDraw.Draw(image)
        for y in range(200):
            shade = int(70 * (1 - y / 200))
            draw.line((0, y, CONFIG["video_width"], y), fill=(150 + shade, 35, 60))
        draw.rectangle((10, 10, 1070, 1910), outline=(255, 215, 0), width=4)
        draw.text((540, 100), label.upper(), font=small_font, anchor="mt", fill="white")
        draw.text((540, 210), f"{beat['emoji']} {beat['name']} {beat['emoji']}", font=title_font, anchor="mt", fill=(255, 215, 0))
        y = 420
        for line in wrap(draw, beat["narration"], text_font, 880):
            draw.text((540, y), line, font=text_font, anchor="mt", fill="white"); y += 68
        y = 1600
        for line in wrap(draw, f"Visual: {beat['visual']}", small_font, 850):
            draw.text((540, y), line, font=small_font, anchor="mt", fill=(210, 210, 210)); y += 44
        draw.text((980, 1840), f"{index}/{len(beats)}", font=small_font, anchor="mt", fill=(180, 180, 180))
        path = directory / f"beat_{index:02d}.png"; image.save(path); paths.append(path)
    return paths


def voiceover(beats: Iterable[Dict[str, object]], path: Path) -> AudioFileClip:
    """Return a cached narration, or generate one through gTTS when absent."""
    if path.exists():
        return AudioFileClip(str(path))
    text = " ".join(str(beat["narration"]) for beat in beats)
    source = path.with_suffix(".source.mp3")
    gTTS(text=text, lang="en", slow=False).save(str(source))
    audio = AudioFileClip(str(source)).fx(vfx.speedx, 1.2)
    audio.write_audiofile(str(path), logger=None)
    audio.close(); source.unlink(missing_ok=True)
    return AudioFileClip(str(path))


def captions(beats: Iterable[Dict[str, object]], directory: Path):
    """Render caption cards with Pillow, avoiding ImageMagick's security policy."""
    directory.mkdir(parents=True, exist_ok=True)
    result, start, index = [], 0.0, 0
    caption_font = font(45)
    for beat in beats:
        words = str(beat["narration"]).split()
        chunks = [" ".join(words[i:i + 8]) for i in range(0, len(words), 8)]
        duration = beat["duration"] / len(chunks)
        for offset, chunk in enumerate(chunks):
            image = Image.new("RGBA", (900, 210), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            lines = wrap(draw, chunk, caption_font, 850)
            draw.multiline_text((450, 105), "\n".join(lines), font=caption_font, anchor="mm", align="center", fill="yellow", stroke_width=3, stroke_fill="black", spacing=8)
            path = directory / f"caption_{index:03d}.png"
            image.save(path); index += 1
            result.append(ImageClip(str(path)).set_position(("center", 1700)).set_start(start + offset * duration).set_duration(duration))
        start += beat["duration"]
    return result


def story_video(beats, name: str, workdir: Path):
    target_duration = sum(beat["duration"] for beat in beats)
    audio = voiceover(beats, workdir / f"voiceover_{name}.mp3")
    # Never let a longer narration extend the requested story timeline.
    audio = audio.subclip(0, min(audio.duration, target_duration))
    clips = []
    for beat, slide in zip(beats, slides(beats, name, workdir / f"slides_{name}")):
        duration = beat["duration"]
        zoom = random.uniform(.02, .05)
        clips.append(ImageClip(str(slide)).set_duration(duration).resize(lambda t: 1 + zoom * t / duration))
    video = concatenate_videoclips(clips, method="compose").subclip(0, min(sum(b["duration"] for b in beats), audio.duration)).set_audio(audio)
    return CompositeVideoClip([video, *captions(beats, workdir / f"captions_{name}")])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="doraemon_834ab_recap.mp4")
    parser.add_argument("--workdir", default="recap_assets")
    parser.add_argument("--duration", type=float, default=90, help="Target total duration in seconds (default: 90)")
    parser.add_argument("--fps", type=int, default=CONFIG["fps"], help="Output frame rate (default: 24)")
    parser.add_argument("--bgm", help="Optional music file, mixed at 30%% volume")
    args = parser.parse_args()
    if args.duration <= 0:
        parser.error("--duration must be greater than zero")
    if args.fps <= 0:
        parser.error("--fps must be greater than zero")
    workdir = Path(args.workdir); workdir.mkdir(exist_ok=True)
    original_duration = sum(beat["duration"] for beat in STORY1_BEATS + STORY2_BEATS)
    scale = args.duration / original_duration
    def scaled(beats):
        return [{**beat, "duration": beat["duration"] * scale} for beat in beats]
    first, second = story_video(scaled(STORY1_BEATS), "GameCreator", workdir), story_video(scaled(STORY2_BEATS), "Halloween", workdir)
    final = concatenate_videoclips([first.fadeout(.5), second.fadein(.5)], method="compose")
    if args.bgm:
        music = AudioFileClip(args.bgm).volumex(.3).set_duration(final.duration)
        final = final.set_audio(CompositeAudioClip([final.audio, music]))
    final.write_videofile(args.output, fps=args.fps, codec="libx264", audio_codec="aac", threads=4, preset="medium")


if __name__ == "__main__":
    main()
