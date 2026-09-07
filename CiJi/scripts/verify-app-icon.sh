#!/usr/bin/env bash
# Run on macOS after Archive to confirm App Store icon requirements.
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "Usage: $0 /path/to/CiJi.app"
  echo "Tip: In Organizer, Show in Finder → Show Package Contents of the archive → Products/Applications/CiJi.app"
  exit 1
fi

ICNS="$APP/Contents/Resources/AppIcon.icns"
PLIST="$APP/Contents/Info.plist"

echo "== Info.plist icon keys =="
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$PLIST" 2>/dev/null || echo "(no CFBundleIconName)"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST" 2>/dev/null || echo "(no CFBundleIconFile)"

if [[ ! -f "$ICNS" ]]; then
  echo "FAIL: missing $ICNS"
  echo "Assets.xcassets AppIcon.appiconset must include walt.e@example.net (1024×1024),"
  echo "and Target build setting ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon."
  exit 1
fi

echo "== ICNS present: $ICNS ($(wc -c < "$ICNS") bytes) =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
iconutil -c iconset -o "$TMP/AppIcon.iconset" "$ICNS"
ls -la "$TMP/AppIcon.iconset"

need512="$TMP/AppIcon.iconset/icon_512x512.png"
need1024="$TMP/AppIcon.iconset/walt.e@example.net"
[[ -f "$need512" ]] || { echo "FAIL: ICNS missing 512×512"; exit 1; }
[[ -f "$need1024" ]] || { echo "FAIL: ICNS missing 512@2x (1024×1024)"; exit 1; }

s512="$(sips -g pixelWidth -g pixelHeight "$need512" | awk '/pixel/{print $2}' | tr '\n' 'x' | sed 's/x$//')"
s1024="$(sips -g pixelWidth -g pixelHeight "$need1024" | awk '/pixel/{print $2}' | tr '\n' 'x' | sed 's/x$//')"
echo "icon_512x512.png => $s512 (expect 512x512)"
echo "walt.e@example.net => $s1024 (expect 1024x1024)"

[[ "$s512" == "512x512" && "$s1024" == "1024x1024" ]] || exit 1
echo "OK: App Store 512 / 512@2x icons are present."
