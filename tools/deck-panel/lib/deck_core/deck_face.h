// The deck screen's model (#621): what each widget shows, decided here from the deck's state so the board layer only
// draws, and compares widget by widget to redraw only what changed (fast fields come at up to 30 a second).
#pragma once

#include <cstdint>
#include <cstring>

#include "deck_core.h"
#include "deck_layout.h"

namespace deck_core {

/// The deck screen's colors, 0xRRGGBB.
namespace palette {
constexpr uint32_t kWhite = 0xFFFFFF, kBlack = 0x000000;
constexpr uint32_t kGray = 0xA0A0A0;   ///< names, the artist, the phase bar's center
constexpr uint32_t kDim = 0x5A5A5A;    ///< an unlit lamp's text
constexpr uint32_t kTrack = 0x262626;  ///< bars, unlit blocks and lamps
constexpr uint32_t kProgress = 0xE0E0E0, kWarning = 0xFF3B30, kLevel = 0x30D158;
/// Lit lamps: play, cue, sync, master, loop.
constexpr uint32_t kLamp[] = {0x30D158, 0xFF9F0A, 0x0A84FF, 0xFFD60A, 0x64D2FF};
}  // namespace palette

constexpr int kLamps = 5;

/// What the deck screen shows. Texts are UTF-8, fitted to the fonts (font_fallback); "" draws nothing. The number texts' sizes fit any long their format
/// can print, as GCC's -Wformat-truncation checks under -Werror (CI's Linux build), though real values are short.
struct Face {
    char deck[12] = "";  ///< "1"-"4"
    uint32_t deck_color = palette::kWhite;  ///< the deck number's, 0xRRGGBB
    char title[kTextBytes] = "";
    char artist[kTextBytes] = "";
    char key[kKeyMax * 4 + 1] = "";
    char bpm[32] = "";
    char tempo[32] = "";
    char elapsed[32] = "";
    char remaining[32] = "";
    int32_t progress_px = 0;  ///< the bar's fill, 0 to layout::kWidth
    uint32_t progress_color = palette::kProgress;  ///< the fill: kWarning in the track's last seconds
    uint32_t beat_color[4] = {palette::kTrack, palette::kTrack, palette::kTrack, palette::kTrack};  ///< each block
    /// Play, cue, sync, master, loop: each lamp's box and text.
    uint32_t lamp_color[kLamps] = {palette::kTrack, palette::kTrack, palette::kTrack, palette::kTrack, palette::kTrack};
    uint32_t lamp_text_color[kLamps] = {palette::kDim, palette::kDim, palette::kDim, palette::kDim, palette::kDim};
    char loop_label[32] = "LOOP";  ///< the loop lamp's text, with the length when there is one: "LOOP 1/2"
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
