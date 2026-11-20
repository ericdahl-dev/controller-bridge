#include "deck_face.h"

#include <cmath>
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

/// A loop's length in beats: whole ("4"), a fraction of one beat ("1/2" … "1/32"), else as it is ("1.5").
template <size_t N>
void loop_text(char (&out)[N], float beats) {
    if (beats <= 0) return;
    const long whole = static_cast<long>(beats + 0.5f);
    if (whole >= 1 && std::fabs(beats - static_cast<float>(whole)) < 0.001f) {
        std::snprintf(out, N, "%ld", whole);
        return;
    }
    for (long below = 2; below <= 64; below *= 2) {
        if (std::fabs(beats - 1.0f / static_cast<float>(below)) < 0.0001f) {
            std::snprintf(out, N, "1/%ld", below);
            return;
        }
    }
    std::snprintf(out, N, "%g", static_cast<double>(beats));
}

float clamp01(float x) { return x < 0 ? 0 : x > 1 ? 1 : x; }

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
    f.progress = clamp01(view.progress);
    f.end_warning = view.remaining > 0 && view.remaining <= kEndWarningSeconds;
    if (view.beat >= 1 && view.beat <= 4) f.beat = view.beat;
    f.playing = view.playing;
    f.cue = view.cue;
    f.sync = view.sync;
    f.master = view.master;
    f.loop = view.loop;
    loop_text(f.loop_length, view.loop_length);
    return f;
}

}  // namespace deck_core
