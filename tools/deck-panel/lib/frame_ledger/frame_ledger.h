// The panel's frame ledger (#662): one record per frame, from the newest feed datagram's arrival to the vsync that
// put its frame on the glass, so lag is measured without a camera and "nothing changed" is told from "missed a frame".
// Kept free of Arduino so it's host-tested; the perf build (-DPANEL_PERF_LOG) feeds it and prints its report in the
// 5 s perf line, never per frame. Times are microseconds on one clock (esp_timer on the board); they may wrap.
#pragma once

#include <cstdint>

namespace frame_ledger {

struct Report {
    uint32_t frames = 0;           // frames that carried feed data to the glass
    uint32_t lag_typical_us = 0;   // arrival to glass, the median
    uint32_t lag_worst_us = 0;
    uint32_t skipped = 0;          // frames that reached the glass a vsync or more late
};

class Ledger {
  public:
    // A feed datagram was read and handed to the core.
    void read(uint32_t us);
    // The frame was handed to the panel.
    void swapped(uint32_t us);
    // The vsync that released the swap: the frame is on the glass.
    void on_glass(uint32_t us);
    // The report since the last take(), and a fresh window.
    Report take();

  private:
    bool pending_ = false;     // a read waits for its frame to reach the glass
    uint32_t pending_us_ = 0;  // when it was read
    Report report_;
};

}  // namespace frame_ledger
