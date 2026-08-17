#!/usr/bin/env bash
# Build AnimeNotify without Gradle. Useful in small/offline environments.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${ANDROID_TOOLS:-/home/user/.android-tools-anime}"
JAVA="${JAVA:-/home/user/.local/lib/python3.11/site-packages/jdk4py/java-runtime/bin/java}"
ANDROID_JAR="${ANDROID_JAR:-$TOOLS/android.jar}"
# This standalone AAPT2 predates Android 15's resource-table encoding. The app
# only references framework resources available in API 30, so use that readable
# table for resource linking while ECJ still compiles against API 35 below.
RESOURCE_JAR="${RESOURCE_JAR:-$TOOLS/repos/sdk/30/public/android.jar}"
ECJ="${ECJ:-$TOOLS/ecj.jar}"
DX="${DX:-$TOOLS/dx.jar}"
AAPT2="${AAPT2:-$TOOLS/aapt2}"
ZIPALIGN="${ZIPALIGN:-$TOOLS/zipalign}"
APKSIGNER="${APKSIGNER:-$TOOLS/apksigner.jar}"
KEYSTORE="${KEYSTORE:-$TOOLS/debug.keystore}"
ZIPALIGN_LIB="${ZIPALIGN_LIB:-$TOOLS/repos/build-tools/linux-x86/lib64}"
WORK="$ROOT/.apk-build"
APP_ID="${APP_ID:-com.animenotify.mobile}"
TARGET_SDK="${TARGET_SDK:-28}"
VERSION_CODE="${VERSION_CODE:-3}"
VERSION_NAME="${VERSION_NAME:-1.0.2}"
OUT="${OUTPUT_APK:-$ROOT/AnimeNotify.apk}"

for file in "$JAVA" "$ANDROID_JAR" "$RESOURCE_JAR" "$ECJ" "$DX" "$AAPT2" "$ZIPALIGN" "$APKSIGNER" "$KEYSTORE"; do
  if [[ ! -e "$file" ]]; then
    echo "Missing build tool: $file" >&2
    exit 1
  fi
done

rm -rf "$WORK"
mkdir -p "$WORK/compiled" "$WORK/generated" "$WORK/classes"

echo "[1/6] Compiling Android resources"
"$AAPT2" compile --dir "$ROOT/app/src/main/res" -o "$WORK/compiled/resources.zip"

echo "[2/6] Linking resources and manifest"
"$AAPT2" link \
  -I "$RESOURCE_JAR" \
  --manifest "$ROOT/app/src/main/AndroidManifest.xml" \
  --java "$WORK/generated" \
  --custom-package com.animenotify.app \
  --rename-manifest-package "$APP_ID" \
  --min-sdk-version 24 \
  --target-sdk-version "$TARGET_SDK" \
  --version-code "$VERSION_CODE" \
  --version-name "$VERSION_NAME" \
  --compile-sdk-version-code 35 \
  --compile-sdk-version-name 15 \
  --no-version-vectors \
  -o "$WORK/resources.apk" \
  "$WORK/compiled/resources.zip"

echo "[3/6] Compiling Java"
find "$ROOT/app/src/main/java" "$WORK/generated" -name '*.java' -print > "$WORK/sources.txt"
"$JAVA" -jar "$ECJ" \
  -source 1.8 -target 1.8 -encoding UTF-8 -proc:none \
  -bootclasspath "$ANDROID_JAR" \
  -d "$WORK/classes" \
  @"$WORK/sources.txt"

echo "[4/6] Converting classes to DEX"
"$JAVA" -jar "$DX" --dex --min-sdk-version=24 \
  --output="$WORK/classes.dex" "$WORK/classes"

cp "$WORK/resources.apk" "$WORK/unaligned.apk"
(
  cd "$WORK"
  zip -q -j unaligned.apk classes.dex
)

echo "[5/6] Zip-aligning APK"
LD_LIBRARY_PATH="$ZIPALIGN_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$ZIPALIGN" -f 4 "$WORK/unaligned.apk" "$WORK/aligned.apk"

echo "[6/6] Signing and verifying APK"
rm -f "$OUT" "$OUT.idsig"
"$JAVA" -jar "$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:$KS_PASS" \
  --key-pass "pass:$KEY_PASS" \
  --min-sdk-version 21 \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled false \
  --v4-signing-enabled false \
  --out "$OUT" \
  "$WORK/aligned.apk"
"$JAVA" -jar "$APKSIGNER" verify --verbose --print-certs \
  --min-sdk-version 21 "$OUT"
LD_LIBRARY_PATH="$ZIPALIGN_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$ZIPALIGN" -c -v 4 "$OUT" >/dev/null

size="$(du -h "$OUT" | cut -f1)"
echo "Built $OUT ($size)"
