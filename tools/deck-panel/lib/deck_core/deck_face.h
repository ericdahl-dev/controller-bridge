// The deck screen's model (#621): what each widget shows, decided here from the deck's state so the board layer only
// draws, and compares widget by widget to redraw only what changed (fast fields come at up to 30 a second).
#pragma once

#include <cstdint>
#include <cstring>

#include "deck_core.h"
#include "deck_layout.h"

namespace deck_core {

/// What the deck screen shows. Texts are UTF-8; "" draws nothing. The number texts' sizes fit any long their format
/// can print, as GCC's -Wformat-truncation checks under -Werror (CI's Linux build), though real values are short.
struct Face {
    char deck[12] = "";  ///< "1"-"4"
    uint32_t color = 0;  ///< the deck number's, 0xRRGGBB
    char title[kTextBytes] = "";
    char artist[kTextBytes] = "";
    char key[kKeyMax * 4 + 1] = "";
    char bpm[32] = "";
    char tempo[32] = "";
    char elapsed[32] = "";
    char remaining[32] = "";
    int32_t progress_px = 0;  ///< the bar's fill, 0 to layout::kWidth
    bool end_warning = false;  ///< the bar in the warning color
    int beat = 0;  ///< the lit block, 1-4; 0 none
    bool playing = false, cue = false, sync = false, master = false, loop = false;  ///< the lamps
    char loop_length[24] = "";
    bool phase_shown = false;
    int32_t phase_px = layout::kPhaseTravel / 2;  ///< the marker's left edge, 0 to layout::kPhaseTravel
    int32_t level_px = 0;  ///< the meter's fill from the bottom, 0 to layout::kMeterH
};

/// The progress bar warns for the track's last this many seconds.
constexpr int32_t kEndWarningSeconds = 30;

/// The text an empty deck shows in the title's place.
constexpr const char* kNoTrack = "No track loaded";

Face face(const DeckView& view);

}  // namespace deck_core
