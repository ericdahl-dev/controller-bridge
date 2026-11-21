#include "beat_clock.h"

namespace deck_core {

void BeatClock::edge(int beat, uint32_t) { beat_ = beat >= 1 && beat <= 4 ? beat : 0; }

int BeatClock::beat_at(uint32_t) const { return beat_; }

}  // namespace deck_core
