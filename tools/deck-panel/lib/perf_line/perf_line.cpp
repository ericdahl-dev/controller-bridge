#include "perf_line.h"

#include <cstdio>

namespace perf_line {

std::string format(const Window& w) {
    char line[320];
    const double seconds = w.ms > 0 ? w.ms / 1000.0 : 1.0;
    char tail[160];
    snprintf(tail, sizeof tail, "%.1f vsyncs/s, %u swap timeouts, feed %u datagrams %u too big, internal free %u",
             w.vsyncs / seconds, static_cast<unsigned>(w.swap_timeouts), static_cast<unsigned>(w.datagrams),
             static_cast<unsigned>(w.too_big), static_cast<unsigned>(w.internal_free));
    if (w.frames.frames == 0) {
        // LVGL doesn't refresh while nothing is invalid: a still screen has no frames to time.
        snprintf(line, sizeof line, "perf: no frames (nothing changed), %s", tail);
        return line;
    }
    const double swaps = w.swaps > 0 ? w.swaps : 1;
    snprintf(line, sizeof line,
             "perf: %.1f frames/s, render avg %.1f ms max %.1f ms, swap wait %.1f ms/frame, draw_bitmap %.2f ms/frame, %s",
             w.frames.framesPerSecond, w.frames.frameAvgMs, w.frames.frameMaxMs, w.swap_wait_us / swaps / 1000.0,
             w.draw_bitmap_us / swaps / 1000.0, tail);
    return line;
}

}  // namespace perf_line
