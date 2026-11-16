#!/bin/bash
# Smoke check for the sandboxed app (#14). A virtual MIDI source/destination stands in for the LC6000 and a UDP
# loopback stands in for Syndicate. Checks that Play goes out as PlayPause and the Play LED comes back.
#
# Usage: scripts/smoke.sh [path/to/ControllerBridge.app]
# Default app: the Release ad-hoc build from `xcodebuild ... -configuration Release -derivedDataPath build`.
# Use Release: a Debug ad-hoc build drops the hardened runtime, so it doesn't test what ships.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:-build/Build/Products/Release/ControllerBridge.app}"
binary="$app/Contents/MacOS/ControllerBridge"
[ -x "$binary" ] || { echo "No app at $app. Build it first (see .github/workflows/ci.yml)."; exit 2; }
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)"
[[ "$entitlements" == *com.apple.security.app-sandbox* ]] || { echo "$app is not sandboxed"; exit 2; }

work="$(mktemp -d)"
trap 'kill "${app_pid:-}" 2>/dev/null || true; rm -rf "$work"' EXIT
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

# Run the binary directly to get its log on stdout; the sandbox still applies.
"$binary" > "$work/app.log" 2>&1 &
app_pid=$!

status=0
wait "$helper_pid" || status=$?
kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
echo "--- app log"; cat "$work/app.log"
exit "$status"
