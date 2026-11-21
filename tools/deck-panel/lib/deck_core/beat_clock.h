// The panel's beat clock (#660): the master clock's beat (1-4) at any time, from the beat edges the feed brings,
// so a box can light when its beat is due, not when a packet happens to arrive. No board here: times are any
// millisecond clock, which may wrap.
#pragma once

#include <cstdint>

#ifndef DECK_PANEL_PREDICT_BEATS
#define DECK_PANEL_PREDICT_BEATS 1
#endif

namespace deck_core {

class BeatClock {
  public:
    /// How many beats past the last edge heard the clock shows when they're due. 1: the next beat lights on time,
    /// and if the master stops, at most one beat shows that didn't happen. 0: never past the last edge, as before
    /// #660. The owner picks after seeing both: build with -DDECK_PANEL_PREDICT_BEATS=0 for the other.
    static constexpr int kPredictBeats = DECK_PANEL_PREDICT_BEATS;
    /// Tempos the clock believes, as a beat's length: 40-300 BPM.
    static constexpr uint32_t kShortestBeatMs = 200, kLongestBeatMs = 1500;

    /// The feed's beat arrived at `at_ms`: a new value is an edge; the same again (a keepalive) is none.
    void edge(int beat, uint32_t at_ms);
    /// The beat to show at `now_ms`, 1-4; 0 for none.
    int beat_at(uint32_t now_ms) const;

  private:
    int beat_ = 0;              ///< the last beat heard
    uint32_t edge_ms_ = 0;      ///< when it was heard
    uint32_t period_ms_ = 0;    ///< a beat's length; 0 until two edges in a row give it
};

}  // namespace deck_core
