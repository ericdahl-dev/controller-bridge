#include "deck_face.h"

#include <cstdio>

namespace deck_core {

namespace {

template <size_t N>
void copy(char (&out)[N], const char* text) {
    std::snprintf(out, N, "%s", text);
}

/// Whole seconds as "m:ss", or "h:mm:ss" past an hour, after `sign`. Negative counts as 0.
template <size_t N>
void time_text(char (&out)[N], const char* sign, int32_t seconds) {
    const long s = seconds < 0 ? 0 : seconds;
    if (s >= 3600) {
        std::snprintf(out, N, "%s%ld:%02ld:%02ld", sign, s / 3600, s / 60 % 60, s % 60);
    } else {
        std::snprintf(out, N, "%s%ld:%02ld", sign, s / 60, s % 60);
    }
}

}  // namespace

Face face(const DeckView& view) {
    Face f;
    if (view.deck >= 1 && view.deck <= 4) std::snprintf(f.deck, sizeof f.deck, "%d", view.deck);
    f.color = view.color;
    if (!view.loaded) {
        // Empty: the deck and "No track loaded", nothing else, never the last track.
        copy(f.title, kNoTrack);
        return f;
    }
    copy(f.title, view.title);
    copy(f.artist, view.artist);
    copy(f.key, view.key);
    // Both arrive at 2 decimals; shown at 2, the panel never rounds them differently from DeckBridge. 0 BPM is
    // unknown, and with it the tempo.
    if (view.bpm > 0) {
        std::snprintf(f.bpm, sizeof f.bpm, "%.2f", static_cast<double>(view.bpm));
        if (view.tempo == 0) {
            copy(f.tempo, "0.00%");
        } else {
            std::snprintf(f.tempo, sizeof f.tempo, "%+.2f%%", static_cast<double>(view.tempo));
        }
    }
    time_text(f.elapsed, "", view.elapsed);
    // 0 is no known length.
    if (view.remaining > 0) time_text(f.remaining, "-", view.remaining);
    return f;
}

}  // namespace deck_core
