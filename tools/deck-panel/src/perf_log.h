// The perf build's serial line (#635), env crowpanel-perf (-DPANEL_PERF_LOG): every 5 s, frames/s, render and swap
// times, vsyncs, swap timeouts, the feed's datagrams and free internal RAM, so a try on the panel has numbers, not
// only eyes. The text is lib/perf_line's, host-tested. Without PANEL_PERF_LOG these do nothing.
#pragma once

#include <cstdint>

namespace perf_log {

// After display_init(): times LVGL's refreshes and flushes.
void begin();

// From the loop, after the feed drain: `datagrams` read by this drain, `too_big` the drain's running count.
void tick(uint32_t now_ms, int datagrams, uint32_t too_big);

}  // namespace perf_log
