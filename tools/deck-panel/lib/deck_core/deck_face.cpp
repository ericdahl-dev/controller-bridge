#include "deck_face.h"

#include <cstdio>

namespace deck_core {

namespace {

template <size_t N>
void copy(char (&out)[N], const char* text) {
    std::snprintf(out, N, "%s", text);
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
    return f;
}

}  // namespace deck_core
