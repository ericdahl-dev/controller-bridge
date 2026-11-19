#!/bin/sh
# Regenerates the drawn display's reference images (#457) from the Swift renderer, JogDisplayRenderer, never from the
# C code under test. Run from anywhere: sh tools/lc6000-display-fw/test/ref/make_refs.sh
# "Other" is rendered with no player type: the C side has no type name, so it draws no badge (Swift would draw the
# name's first four letters).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
kit="$here/../../../../Packages/ControllerBridgeKit"
swift build --package-path "$kit" --product jog-reference >&2
bin=$(swift build --package-path "$kit" --show-bin-path)/jog-reference
"$bin" 2 255 0 0 track "$here/deck2-red-track.ppm"
"$bin" 4 0 128 255 empty "$here/deck4-blue-empty.ppm"
"$bin" 1 255 255 255 midiclip "$here/deck1-white-midi.ppm"
"$bin" 3 0 200 80 - "$here/deck3-green-other.ppm"
"$bin" 1 255 128 0 osc "$here/deck1-orange-osc.ppm"
"$bin" 3 180 0 255 sequencer "$here/deck3-purple-seq.ppm"
# The waiting look (#464): our logo, whatever the deck.
"$bin" 2 255 0 0 track "$here/stale.ppm" stale
# The text (#458): a short title, one line at 20 px, two lines, cut lines with no key or BPM, and accents.
"$bin" 2 255 0 0 track "$here/text-strobe.ppm" title=Strobe artist=Deadmau5 key=F#m bpm=128
"$bin" 2 255 0 0 track "$here/text-night-drive.ppm" "title=Night Drive" "artist=Café del Mar" key=11B bpm=90
"$bin" 1 255 255 255 track "$here/text-ten.ppm" "title=Ten (Original Club Mix)" "artist=Mark Knight" key=8A bpm=124.5
"$bin" 3 0 200 80 track "$here/text-cut.ppm" "title=Mark Knight Underworld Sander Van Doorn Remix Edition" \
    "artist=Wolfgang Amadeus Mozart and the Vienna Philharmonic"
"$bin" 4 0 128 255 track "$here/text-accents.ppm" "title=Tänzer aus Tübingen" "artist=Léa Seydoux & “Don’t”" key=Ebm bpm=174
"$bin" 3 0 200 80 Automation "$here/text-automation.ppm"
sips -s format png -Z 396 "$here/text-ten.ppm" --out "$here/text-ten-preview.png" >/dev/null
# A PNG of the waiting look, for people to look at (the PR, the README); the tests read the PPM.
sips -s format png -Z 396 "$here/stale.ppm" --out "$here/stale-preview.png" >/dev/null
# The live elements (#459): the lit master beat and the marker, as the Diagnostics simulator draws them, from the
# live-reference tool beside this script (the Kit's JogDisplayRenderer.simulatorImage). Deck 4, empty: its header is
# the chip alone, and nothing else is drawn near the ring.
swift build --package-path "$here/live-reference" >&2
live=$(swift build --package-path "$here/live-reference" --show-bin-path)/live-reference
for beat in 1 2 3 4; do
    "$live" 4 0 128 255 empty "$beat" - "$here/deck4-blue-empty-beat$beat.ppm"
done
for needle in 0 4096 8192 12288 1500; do
    "$live" 4 0 128 255 empty - "$needle" "$here/deck4-blue-empty-needle$needle.ppm"
done
# The marker over a lit section, at an angle that folds back from the last quarter turn.
"$live" 4 0 128 255 empty 3 11000 "$here/deck4-blue-empty-beat3-needle11000.ppm"
# The level meter (#461): silence, mid with a held peak above, high (yellow, the tick over it), clip.
for meter in "0 0" "64 90" "110 120" "127 127"; do
    set -- $meter
    "$live" 4 0 128 255 empty - - "$1" "$2" "$here/deck4-blue-empty-meter$1-$2.ppm"
done
# The phase rule (#462): in phase (the tick), a hundredth of a beat behind and ahead, a tenth behind, and the most
# ahead (the whole half). Unknown is the plain rule, as every reference above draws it.
for phase in 0 -164 164 -1638 8191; do
    "$live" 4 0 128 255 empty - - phase=$phase "$here/deck4-blue-empty-phase$phase.ppm"
done
# A PNG of the five, for people to look at (the PR): the rule of each, at 4×.
python3 -I - "$here" <<'PY'
import sys
here = sys.argv[1]
names = ["0", "-164", "164", "-1638", "8191"]
x0, y0, w, h, k = 30, 119, 138, 16, 4
rows = []
for name in names:
    data = open(f"{here}/deck4-blue-empty-phase{name}.ppm", "rb").read()
    pixels = data[data.index(b"255\n") + 4:]
    for y in range(y0, y0 + h):
        line = b"".join(pixels[(y * 198 + x) * 3:(y * 198 + x) * 3 + 3] * k for x in range(x0, x0 + w))
        rows += [line] * k
    rows += [b"\x40\x40\x40" * (w * k)] * 2
open(f"{here}/phase-preview.ppm", "wb").write(b"P6\n%d %d\n255\n" % (w * k, len(rows)) + b"".join(rows))
PY
sips -s format png "$here/phase-preview.ppm" --out "$here/phase-preview.png" >/dev/null
rm "$here/phase-preview.ppm"
# Track time (#460): the remaining time and the progress ring. The start, the middle, an unknown length (nothing), the
# last minute's warning in its red half and its normal half, a red deck's normal half (the ring white), and the needle
# crossing the ring (the needle on top).
"$live" 4 0 128 255 empty - - "time=0/165" "$here/deck4-blue-empty-time0-165.ppm"
"$live" 4 0 128 255 empty - - "time=83/165" "$here/deck4-blue-empty-time83-165.ppm"
"$live" 4 0 128 255 empty - - "time=42/0" "$here/deck4-blue-empty-time42-0.ppm"
"$live" 4 0 128 255 empty - - "time=135/165" look=red "$here/deck4-blue-empty-time135-165-red.ppm"
"$live" 4 0 128 255 empty - - "time=135/165" look=normal "$here/deck4-blue-empty-time135-165-normal.ppm"
"$live" 2 255 0 0 empty - - "time=135/165" look=normal "$here/deck2-red-empty-time135-165-normal.ppm"
"$live" 4 0 128 255 empty - 4096 "time=83/165" "$here/deck4-blue-empty-time83-165-needle4096.ppm"
# Long tracks: minutes past 59 stay minutes, "-99:59" the widest.
"$live" 4 0 128 255 empty - - "time=0/5999" "$here/deck4-blue-empty-time0-5999.ppm"
