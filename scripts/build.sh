#!/bin/bash
# Build Prims Paste.app into ~/Applications.
# Signed as Developer ID Application: Eidos AGI LLC.
set -eo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/Prims Paste.app"
BIN="$PKG/.build/release/PrimsPaste"
CLI="$PKG/.build/release/prims-paste"
TEAM="Y6CQ4SWPWM"
ID="Developer ID Application: Eidos AGI LLC ($TEAM)"

cd "$PKG"
rm -f "$BIN" "$CLI"
swift build -c release --product PrimsPaste
swift build -c release --product prims-paste

if ! "$BIN" --selftest; then
  echo "selftest FAILED — not installing" >&2
  exit 1
fi

osascript -e 'quit app "Prims Paste"' 2>/dev/null || true
osascript -e 'quit app "SafePaste"' 2>/dev/null || true
pkill -f "Prims Paste.app/Contents/MacOS/PrimsPaste" 2>/dev/null || true
sleep 0.3

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN" "$APP/Contents/MacOS/PrimsPaste"
cp "$CLI" "$APP/Contents/Helpers/prims-paste"
chmod 755 "$APP/Contents/MacOS/PrimsPaste" "$APP/Contents/Helpers/prims-paste"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
test -f "$PKG/brand/AppIcon.icns" || { echo "FATAL: brand/AppIcon.icns missing — run scripts/render-brand.py" >&2; exit 1; }
cp "$PKG/brand/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$PKG/brand/mark-paste.png" "$APP/Contents/Resources/PasteMark.png"
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

mkdir -p "$HOME/.local/bin"
ln -sfn "$APP/Contents/Helpers/prims-paste" "$HOME/.local/bin/prims-paste"

echo "built $APP"
echo "signed $ID"
echo "cli    $HOME/.local/bin/prims-paste"
