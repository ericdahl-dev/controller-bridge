#!/bin/sh
# Tests scripts/tag-external.sh (#244): only an annotated tag whose message says [external] sends a release out to
# external testers. A plain tag, a lightweight tag, or a message without the marker is internal only.
#   scripts/test-tag-external.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

git -C "$work" init -q
git -C "$work" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
tag() { git -C "$work" -c user.name=t -c user.email=t@example.invalid tag "$@"; }
tag v1.0.0                                              # lightweight
tag -a v1.0.1 -m "Internal build for the jog display"   # annotated, no marker
tag -a v1.0.2 -m "Release 1.0.2 [external]"              # annotated, marker
tag -a v1.0.3 -m "Mentions external but not the marker"
tag -a v1.0.4 -m "Release notes

Ship it. [EXTERNAL]"                                     # marker on a later line, any case

check() {
  got="$(cd "$work" && "$here/tag-external.sh" "$1")"
  if [ "$got" = "$2" ]; then echo "ok   $1 -> $got"; else echo "FAIL $1: expected $2, got $got"; failures=$((failures + 1)); fi
}
check v1.0.0 false
check v1.0.1 false
check v1.0.2 true
check v1.0.3 false
check v1.0.4 true
check v9.9.9 false   # no such tag: internal only, never out

[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
