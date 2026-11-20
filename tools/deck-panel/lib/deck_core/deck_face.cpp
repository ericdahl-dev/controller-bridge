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

/// `x`, taken at 2 decimals, in tenths rounded half away from zero: 128.25 is 1283, -2.55 is -26.
long tenths(float x) {
    const long hundredths = std::lround(static_cast<double>(x) * 100);
    return (hundredths + (hundredths < 0 ? -5 : 5)) / 10;
}

/// `x` at one decimal, without its sign, after `sign` and before `unit`.
template <size_t N>
void tenths_text(char (&out)[N], const char* sign, float x, const char* unit = "") {
    const long signed_tenths = tenths(x);
    const long t = signed_tenths < 0 ? -signed_tenths : signed_tenths;
    std::snprintf(out, N, "%s%ld.%ld%s", sign, t / 10, t % 10, unit);
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
    // One decimal (the owner's look at #633). Both arrive at 2 decimals; rounded from those, half away from zero, so
    // the result doesn't depend on how the float holds them. 0 BPM is unknown, and with it the tempo.
    if (view.bpm > 0) {
        tenths_text(f.bpm, "", view.bpm);
        const long tempo = tenths(view.tempo);
        if (tempo == 0) {
            copy(f.tempo, "0.0%");
        } else {
            tenths_text(f.tempo, tempo > 0 ? "+" : "-", view.tempo, "%");
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
    // Below 0 is unknown (-1): no marker, never one parked in the middle as if in phase.
    f.phase_shown = view.phase >= 0;
    if (f.phase_shown) f.phase = clamp01(view.phase);
    f.level = clamp01(view.level);
    return f;
}

}  // namespace deck_core
