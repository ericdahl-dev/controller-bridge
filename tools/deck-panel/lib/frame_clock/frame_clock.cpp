#include "frame_clock.h"

namespace frame_clock {

void Clock::step(Board& board) {
    uint32_t count = 0;
    uint32_t us = 0;
    board.wait_latch(count, us);
    board.read_feed();
    board.render();
    board.refresh();
    board.chores(us + period_us_ - guard_us_);
}

}  // namespace frame_clock
