#!/bin/bash
# Smoke check for the sandboxed app (#14). A virtual MIDI source/destination stands in for the LC6000 and a UDP
# loopback stands in for Syndicate. Checks that Play goes out as PlayPause and the Play LED comes back, on layer 1 and
# after a switch to layer 2, on the controls port and never on the unit's "… WD" port.
#
# Usage: scripts/smoke.sh [path/to/ControllerBridge.app]
# Default app: the Release ad-hoc build from `xcodebuild ... -configuration Release -derivedDataPath build`.
# Use Release: a Debug ad-hoc build drops the hardened runtime, so it doesn't test what ships.
#
# It pins the app to the helper's virtual MIDI device by editing the app's saved settings for the run (#86), and puts
# the user's settings back on exit, pass or fail. Only a SIGKILL skips that; then run
#   defaults delete dev.ericdahl.ControllerBridge settings.v1
# to go back to automatic devices.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-build/Build/Products/Release/ControllerBridge.app}"
binary="$app/Contents/MacOS/ControllerBridge"
[ -x "$binary" ] || { echo "No app at $app. Build it first (see .github/workflows/ci.yml)."; exit 2; }
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)"
[[ "$entitlements" == *com.apple.security.app-sandbox* ]] || { echo "$app is not sandboxed"; exit 2; }

work="$(mktemp -d)"
domain=dev.ericdahl.ControllerBridge
saved_prefs=""
cleanup() {
  kill "${app_pid:-}" 2>/dev/null || true
  # Put the user's own settings back, whatever happened (#86).
  if [ -n "$saved_prefs" ]; then
    defaults delete "$domain" 2>/dev/null || true
    [ "$saved_prefs" = "none" ] || defaults import "$domain" "$work/prefs-backup.plist"
  fi
  rm -rf "$work"
}
trap cleanup EXIT
swiftc -O scripts/smoke/SmokeHelper.swift -o "$work/smoke-helper"

# Fail fast if something already holds the ports.
if lsof -nP -iUDP:9090 -iUDP:9096 >/dev/null 2>&1; then
  echo "UDP 9090 or 9096 is already in use (is Syndicate or another bridge running?)"; lsof -nP -iUDP:9090 -iUDP:9096; exit 2
fi

"$work/smoke-helper" "${SMOKE_LAUNCH_TIMEOUT:-20}" > >(tee "$work/helper.log") 2>&1 &
helper_pid=$!
until grep -q READY "$work/helper.log" 2>/dev/null; do
  kill -0 "$helper_pid" 2>/dev/null || { wait "$helper_pid"; exit 1; }
  sleep 0.1
done

# With no real LC6000 attached, run controller 1 with automatic devices, as on a real unit, so the app itself must pick
# the controls ports over the WD ones (#143); pinned devices skip that choice. With one attached, pin controller 1 to
# the helper's controls ports (#86), so the real unit can't take their place; the helper says the automatic case is
# skipped. SMOKE_REQUIRE_AUTOMATIC=1 (CI) fails instead of skipping. Either way the entry follows layers by default,
# so it runs four layers. The user's settings are saved first and restored on exit.
ready="$(grep -m1 READY "$work/helper.log")"
if defaults export "$domain" "$work/prefs-backup.plist" 2>/dev/null; then saved_prefs="yes"; else saved_prefs="none"; fi
mode="$(sed -nE 's/.*mode=([a-z]+).*/\1/p' <<<"$ready")"
if [ "$mode" = automatic ]; then
  settings="$(cat scripts/smoke/settings-template.json)"
else
  [ "${SMOKE_REQUIRE_AUTOMATIC:-0}" = 1 ] && { echo "A real LC6000 is attached, but SMOKE_REQUIRE_AUTOMATIC=1 needs the automatic case."; exit 1; }
  input_id="$(sed -nE 's/.*input=(-?[0-9]+).*/\1/p' <<<"$ready")"
  output_id="$(sed -nE 's/.*output=(-?[0-9]+).*/\1/p' <<<"$ready")"
  [ -n "$input_id" ] && [ -n "$output_id" ] || { echo "The helper didn't report its endpoint ids: $ready"; exit 1; }
  settings="$(sed -e "s/__INPUT_ID__/$input_id/" -e "s/__OUTPUT_ID__/$output_id/" scripts/smoke/settings-pinned-template.json)"
fi
defaults write "$domain" settings.v1 -data "$(printf '%s' "$settings" | xxd -p | tr -d '\n')"

# Run the binary directly to get its log on stdout; the sandbox still applies.
"$binary" > "$work/app.log" 2>&1 &
app_pid=$!

status=0
wait "$helper_pid" || status=$?
kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
echo "--- app log"; cat "$work/app.log"
exit "$status"
