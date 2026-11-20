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
    return f;
}

}  // namespace deck_core
