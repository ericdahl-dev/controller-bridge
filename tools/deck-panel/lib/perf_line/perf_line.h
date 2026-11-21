// The perf build's serial line (#635, -DPANEL_PERF_LOG): one window's numbers as text. Kept free of Arduino so it's
// host-tested; src/perf_log.cpp gathers the numbers and prints it every 5 s.
#pragma once

#include <cstdint>
#include <string>

#include "bounce_budget.h"
#include "frame_clock.h"
#include "frame_ledger.h"
#include "scan_watch.h"


namespace perf_line {

struct Window {
    uint32_t ms = 0;                // how long the window was
    uint32_t frames = 0;            // LVGL refreshes in it that drew something
    uint64_t frame_us = 0;          // their time, start to end (a release still outstanding waits inside, #663)
    uint32_t frame_max_us = 0;
    uint32_t vsyncs = 0;            // the panel's (39 a second at 16 MHz, drawing or not)
    uint32_t swaps = 0;             // frames handed to the panel
    uint32_t swap_timeouts = 0;     // swaps the panel never released within 60 ms
    uint64_t swap_wait_us = 0;      // LVGL waiting for a release
    uint64_t draw_bitmap_us = 0;    // handing frames over
    uint32_t datagrams = 0;         // feed datagrams read; lwIP's own drops aren't visible here
    uint32_t too_big = 0;           // feed datagrams dropped for size
    uint32_t internal_free = 0;     // bytes
    scan_watch::Report scan;        // the scan-out's steadiness
    uint32_t copy_budget_us = 0;    // a bounce chunk's deadline
    bounce_budget::Report copy;     // the bounce copies against it; no chunks when the build can't time them
    frame_ledger::Report ledger;    // feed data's arrival to glass (#662)
    frame_clock::Report clock;      // the frame clock's frames, late ones, missed latches, waits no latch ended (#663)
};

std::string format(const Window& w);

}  // namespace perf_line
