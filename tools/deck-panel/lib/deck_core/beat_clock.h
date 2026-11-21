// The panel's beat clock (#660): the master clock's beat (1-4) at any time, from the beat edges the feed brings,
// so a box can light when its beat is due, not when a packet happens to arrive. No board here: times are any
// millisecond clock, which may wrap.
#pragma once

#include <cstdint>

namespace deck_core {

class BeatClock {
  public:
    /// The feed's beat arrived at `at_ms`: a new value is an edge; the same again (a keepalive) is none.
    void edge(int beat, uint32_t at_ms);
    /// The beat to show at `now_ms`, 1-4; 0 for none.
    int beat_at(uint32_t now_ms) const;

  private:
    int beat_ = 0;
};

}  // namespace deck_core
