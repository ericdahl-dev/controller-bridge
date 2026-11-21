#include "beat_clock.h"

namespace deck_core {

namespace {

int next(int beat) { return beat % 4 + 1; }

}  // namespace

void BeatClock::edge(int beat, uint32_t at_ms) {
    if (beat < 1 || beat > 4) {
        beat_ = 0;
        period_ms_ = 0;
        return;
    }
    if (beat == beat_) return;  // a keepalive
    if (beat_ != 0 && beat == next(beat_)) {
        const uint32_t interval = at_ms - edge_ms_;  // unsigned: the clock wrapping is no jump
        if (interval >= kShortestBeatMs && interval <= kLongestBeatMs) period_ms_ = interval;
    }
    beat_ = beat;
    edge_ms_ = at_ms;
}

int BeatClock::beat_at(uint32_t now_ms) const {
    if (beat_ == 0 || period_ms_ == 0) return beat_;
    const int32_t since = static_cast<int32_t>(now_ms - edge_ms_);
    if (since <= 0) return beat_;
    uint32_t ahead = static_cast<uint32_t>(since) / period_ms_;
    if (ahead > static_cast<uint32_t>(kPredictBeats)) ahead = kPredictBeats;
    int beat = beat_;
    for (uint32_t i = 0; i < ahead; ++i) beat = next(beat);
    return beat;
}

}  // namespace deck_core
