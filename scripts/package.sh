#!/bin/bash
# Builds DroidMirror.app (universal) with scrcpy-server and adb bundled. Run on macOS with Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRCPY_VERSION=5.0.1
OUT=dist
APP="$OUT/DroidMirror.app"
WORK=$(mktemp -d)

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/DroidMirror

rm -rf "$OUT" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/platform-tools"
cp "$BIN" "$APP/Contents/MacOS/DroidMirror"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon
ICONSET="$WORK/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# scrcpy-server (must match ScrcpySession.serverVersion)
curl -fsSL -o "$WORK/scrcpy-server" "https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION/scrcpy-server-v$SCRCPY_VERSION"
if curl -fsSL -o "$WORK/SHA256SUMS.txt" "https://github.com/Genymobile/scrcpy/releases/download/v$SCRCPY_VERSION/SHA256SUMS.txt"; then
  expected=$(grep "scrcpy-server-v$SCRCPY_VERSION\$" "$WORK/SHA256SUMS.txt" | awk '{print $1}')
  actual=$(shasum -a 256 "$WORK/scrcpy-server" | awk '{print $1}')
  echo "scrcpy-server sha256 $actual (expected $expected)"
  [ -z "$expected" ] || [ "$expected" = "$actual" ] || { echo "checksum mismatch"; exit 1; }
fi
cp "$WORK/scrcpy-server" "$APP/Contents/Resources/scrcpy-server"

# adb from Google's platform-tools
curl -fsSL -o "$WORK/pt.zip" "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -q "$WORK/pt.zip" -d "$WORK"
cp "$WORK/platform-tools/adb" "$APP/Contents/Resources/platform-tools/adb"
cp "$WORK/platform-tools/NOTICE.txt" "$APP/Contents/Resources/platform-tools/" 2>/dev/null || true
lipo -info "$APP/Contents/Resources/platform-tools/adb"
lipo -info "$APP/Contents/MacOS/DroidMirror"

codesign --force -s - "$APP/Contents/Resources/platform-tools/adb"
codesign --force -s - "$APP"
(cd "$OUT" && ditto -c -k --keepParent DroidMirror.app DroidMirror.zip)
echo "Built $OUT/DroidMirror.zip"
