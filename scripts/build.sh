#!/bin/bash
# Build Prims Paste.app into ~/Applications.
# Signed as Developer ID Application: Eidos AGI LLC.
set -eo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/Prims Paste.app"
BIN="$PKG/.build/release/PrimsPaste"
TEAM="Y6CQ4SWPWM"
ID="Developer ID Application: Eidos AGI LLC ($TEAM)"

cd "$PKG"
rm -f "$BIN"
swift build -c release --product PrimsPaste

if ! "$BIN" --selftest; then
  echo "selftest FAILED — not installing" >&2
  exit 1
fi

osascript -e 'quit app "Prims Paste"' 2>/dev/null || true
osascript -e 'quit app "SafePaste"' 2>/dev/null || true
pkill -f "Prims Paste.app/Contents/MacOS/PrimsPaste" 2>/dev/null || true
sleep 0.3

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PrimsPaste"
chmod 755 "$APP/Contents/MacOS/PrimsPaste"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

security find-certificate -c "$ID" >/dev/null 2>&1 || {
  echo "FATAL: signing identity '$ID' not in keychain — refusing to ad-hoc sign." >&2
  exit 1
}
codesign --force --deep --options runtime --timestamp \
  --entitlements "$PKG/PrimsPaste.entitlements" \
  -s "$ID" "$APP"

actual="$(codesign -dv --verbose=4 "$APP" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ "$actual" != "$TEAM" ]]; then
  echo "FATAL: TeamIdentifier is '$actual', expected $TEAM" >&2
  exit 1
fi

echo "built $APP"
echo "signed $ID"
