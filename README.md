# AnimeNotify

A lightweight native Android airing calendar and reminder app. The ready-to-install APK is **[`AnimeNotify.apk`](./AnimeNotify.apk)**.

## Features

- Today plus the next seven days of anime airing times, shown in the device timezone
- Public AniList schedule data with a per-day offline cache
- Clearly labelled preview lineup if the first live request cannot connect
- Search, cover art, episode details, and direct AniList links
- One-tap local follow/unfollow controls
- Configurable reminders 5, 15, or 30 minutes before airtime
- Alarm restoration after reboot or app update
- No account, ads, analytics, or third-party runtime libraries

## Install

1. Download `AnimeNotify.apk` to an Android phone or tablet running Android 7.0 or newer.
2. Open it and allow installation from the browser or file manager if Android asks.
3. Allow notifications when following the first show.

The included APK is the `1.0.1` compatibility release. It uses the unique package ID `com.animenotify.mobile`, includes both v1 and v2 signatures for older vendor installers, targets Android 9 (API 28), and supports Android 7.0+ (API 24). It is zip-aligned and signed for direct installation.

## Build

The project is a standard Java Android application (`:app`) configured for Android Gradle Plugin 8.7.3. In Android Studio, open this directory and build the app normally.

A self-contained shell pipeline is also included for this workspace:

```bash
./tools/build_apk.sh
```

It compiles resources and Java, creates DEX bytecode, aligns the package, signs it, verifies it, and writes `AnimeNotify.apk` at the repository root. Tool paths can be overridden with the environment variables documented at the top of the script.

## Data and privacy

AnimeNotify queries AniList's public GraphQL API and downloads cover images. Followed shows and schedule caches remain in local app storage. Approximate, battery-friendly Android alarms are used, so notification delivery can vary slightly depending on device power settings.

---

## Legacy Doraemon recap generator

This repository also retains the original Python Doraemon recap project. To use it, install Python 3.9+, FFmpeg, and the dependencies in `requirements.txt`, then run:

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python doraemon_recap_generator.py --output doraemon_834ab_recap.mp4
```
