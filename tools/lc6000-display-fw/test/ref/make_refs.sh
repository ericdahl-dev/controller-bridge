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
