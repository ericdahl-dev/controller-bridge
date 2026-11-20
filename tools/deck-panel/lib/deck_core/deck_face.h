// The deck screen's model (#621): what each widget shows, decided here from the deck's state so the board layer only
// draws, and compares widget by widget to redraw only what changed (fast fields come at up to 30 a second).
#pragma once

#include <cstdint>
#include <cstring>

#include "deck_core.h"

namespace deck_core {

/// What the deck screen shows. Texts are UTF-8; "" draws nothing.
struct Face {
    char deck[4] = "";  ///< "1"-"4"
    uint32_t color = 0;  ///< the deck number's, 0xRRGGBB
    char title[kTextBytes] = "";
    char artist[kTextBytes] = "";
    char key[kKeyMax * 4 + 1] = "";
    char bpm[12] = "";
    char tempo[12] = "";
    char elapsed[16] = "";
    char remaining[16] = "";
    float progress = 0;  ///< the bar's fill, 0-1
    bool end_warning = false;  ///< the bar in the warning color
    int beat = 0;  ///< the lit block, 1-4; 0 none
    bool playing = false, cue = false, sync = false, master = false, loop = false;  ///< the lamps
    char loop_length[8] = "";
    bool phase_shown = false;
    float phase = 0.5f;  ///< the phase marker's place, 0-1, 0.5 in the middle
    float level = 0;  ///< the meter's fill, 0-1
};

/// The progress bar warns for the track's last this many seconds.
constexpr int32_t kEndWarningSeconds = 30;

/// The text an empty deck shows in the title's place.
constexpr const char* kNoTrack = "No track loaded";

Face face(const DeckView& view);

}  // namespace deck_core
