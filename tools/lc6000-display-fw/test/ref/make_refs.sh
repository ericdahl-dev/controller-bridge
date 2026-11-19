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
