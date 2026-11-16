#!/bin/sh
# Checks what App Store Connect refuses a Mac build for, before any upload: version and build numbers, the export
# compliance and category keys, no Dock icon, the privacy manifest, the app icon, and the sandbox entitlements.
# Ported from ShowRecorder's preflight, Mac only.
#   scripts/preflight.sh path/to/ControllerBridge.xcarchive   (or path/to/ControllerBridge.app)
# Tested by scripts/test-preflight.sh.
set -eu

target="${1:?usage: scripts/preflight.sh <app or xcarchive>}"
fail=0
bad() { echo "FAIL: $1"; fail=1; }
ok() { echo "ok:   $1"; }

case "$target" in
  *.xcarchive) app=$(ls -d "$target"/Products/Applications/*.app 2>/dev/null | head -n 1) ;;
  *) app="$target" ;;
esac
[ -n "$app" ] && [ -f "$app/Contents/Info.plist" ] || { echo "No Mac app found at $target"; exit 2; }
echo "== Checking $app"

plist="$app/Contents/Info.plist"
resources="$app/Contents/Resources"
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }

version=$(read_key CFBundleShortVersionString)
build=$(read_key CFBundleVersion)
case "$version" in ''|*'$('*) bad "CFBundleShortVersionString is '$version'" ;; *) ok "version $version" ;; esac
if echo "$build" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then ok "build number $build"
else bad "CFBundleVersion is '$build' (must be 1 to 3 dot-separated whole numbers)"; fi

compliance=$(read_key ITSAppUsesNonExemptEncryption)
case "$compliance" in true|false) ok "ITSAppUsesNonExemptEncryption = $compliance" ;;
  *) bad "ITSAppUsesNonExemptEncryption is missing from Info.plist" ;; esac

category=$(read_key LSApplicationCategoryType)
[ -n "$category" ] && ok "LSApplicationCategoryType = $category" || bad "LSApplicationCategoryType is missing (the Mac App Store needs it)"

# A menu-bar app: no Dock icon.
[ "$(read_key LSUIElement)" = true ] && ok "LSUIElement = true" || bad "LSUIElement is not true (the app would show in the Dock)"

manifest="$resources/PrivacyInfo.xcprivacy"
if [ -f "$manifest" ]; then
  plutil -lint "$manifest" >/dev/null && ok "privacy manifest is valid" || bad "PrivacyInfo.xcprivacy is not a valid plist"
else
  bad "PrivacyInfo.xcprivacy is not in the app bundle"
fi

if [ -n "$(read_key CFBundleIconName)" ] && [ -f "$resources/Assets.car" ]; then ok "app icon compiled into Assets.car"
else bad "no compiled app icon (CFBundleIconName or Assets.car missing)"; fi

# The Mac App Store refuses an app without the sandbox; the bridge needs to send OSC and to listen for feedback.
# A signed bundle is sealed (_CodeSignature); an executable signed on its own, as the linker does, isn't enough.
if [ -d "$app/Contents/_CodeSignature" ] && codesign -d "$app" >/dev/null 2>&1; then
  entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
  for key in app-sandbox network.client network.server; do
    printf '%s' "$entitlements" | grep -q "com.apple.security.$key</key><true/>" \
      && ok "signed with com.apple.security.$key" || bad "signed without com.apple.security.$key"
  done
else
  bad "the app is not signed, so its entitlements can't be checked"
fi

[ "$fail" = 0 ] && echo "== Preflight passed" || { echo "== Preflight failed"; exit 1; }
