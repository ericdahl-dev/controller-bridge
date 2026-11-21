#include "perf_line.h"

#include <cstdio>

namespace perf_line {

std::string format(const Window& w) {
    char line[680];
    const double seconds = w.ms > 0 ? w.ms / 1000.0 : 1.0;
    char copy[144];
    if (w.copy.chunks == 0) {
        snprintf(copy, sizeof copy, "copy not timed");
    } else {
        char where[48] = "";
        if (w.copy.late > 0) {
            snprintf(where, sizeof where, " (%u drawing, %u at the turn)", static_cast<unsigned>(w.copy_late_drawing),
                     static_cast<unsigned>(w.copy_late_turn));
        }
        snprintf(copy, sizeof copy, "copy worst %u of %u us (margin %d) %u late%s",
                 static_cast<unsigned>(w.copy.worst_us), static_cast<unsigned>(w.copy_budget_us),
                 static_cast<int>(w.copy.margin_us), static_cast<unsigned>(w.copy.late), where);
    }
    char lag[80];
    if (w.ledger.frames == 0) {
        snprintf(lag, sizeof lag, "no feed frames");
    } else {
        snprintf(lag, sizeof lag, "lag %.1f worst %.1f ms, %u of %u frames skipped", w.ledger.lag_typical_us / 1000.0,
                 w.ledger.lag_worst_us / 1000.0, static_cast<unsigned>(w.ledger.skipped),
                 static_cast<unsigned>(w.ledger.frames));
    }
    char tail[520];
    snprintf(tail, sizeof tail,
             "%.1f vsyncs/s, %u swap timeouts, scan lag %.1f-%.1f ms, vsync %.1f-%.1f ms, %u resyncs, %s, "
             "feed %u datagrams %u too big, %s, clock %u frames %u late %u missed %u no latch, internal free %u",
             w.vsyncs / seconds, static_cast<unsigned>(w.swap_timeouts), w.scan.lag_min_us / 1000.0,
             w.scan.lag_max_us / 1000.0, w.scan.vsync_min_us / 1000.0, w.scan.vsync_max_us / 1000.0,
             static_cast<unsigned>(w.scan.resyncs), copy, static_cast<unsigned>(w.datagrams),
             static_cast<unsigned>(w.too_big), lag, static_cast<unsigned>(w.clock.frames),
             static_cast<unsigned>(w.clock.late), static_cast<unsigned>(w.clock.missed),
             static_cast<unsigned>(w.clock.no_latch), static_cast<unsigned>(w.internal_free));
    if (w.frames == 0) {
        // LVGL doesn't refresh while nothing is invalid: a still screen has no frames to time.
        snprintf(line, sizeof line, "perf: no frames (nothing changed), %s", tail);
        return line;
    }
    const double swaps = w.swaps > 0 ? w.swaps : 1;
    snprintf(line, sizeof line,
             "perf: %.1f frames/s, frame avg %.1f ms max %.1f ms (swap wait %.1f), draw_bitmap %.2f ms/frame, %s",
             w.frames / seconds, w.frame_us / 1000.0 / w.frames, w.frame_max_us / 1000.0,
             w.swap_wait_us / swaps / 1000.0, w.draw_bitmap_us / swaps / 1000.0, tail);
    return line;
}

}  // namespace perf_line
