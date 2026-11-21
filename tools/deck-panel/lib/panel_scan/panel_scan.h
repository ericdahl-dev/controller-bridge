// The panel's scan (#666): its timing, the two framebuffers' swaps, the frame boundaries the frame clock waits on, and
// the health of it all, in one module. Inside: frame_pacing (the timing), swap_gate (the swap handshake), scan_watch
// (vsync and frame-end steadiness) and bounce_budget (the copy's deadline). Under it, a Panel: esp_lcd on the board, a
// scripted timeline in the tests. Kept free of Arduino, FreeRTOS and esp_lcd, so it's host-tested.
#pragma once

#include <cstdint>

#include "frame_pacing.h"

namespace panel_scan {

/// What the panel is started with.
struct Config {
    frame_pacing::Timing timing;
    /// Pixels per bounce chunk, copied out of PSRAM by an interrupt; 0 for none (the GDMA reads the framebuffers).
    uint32_t bounce_px;
};

/// The two things the loop waits on: a swap's release, and a frame boundary (a latch or a vsync).
enum class Signal { release = 0, frame = 1 };

/// The panel under the scan: esp_lcd and two binary semaphores on the board, a timeline in the tests.
struct Panel {
    virtual ~Panel() = default;
    virtual bool start(const Config& config) = 0;
    /// The hidden framebuffer, drawn, goes to the panel (esp_lcd_panel_draw_bitmap).
    virtual void hand_over() = 0;
    /// From an interrupt: wakes a take of `signal`. Binary: several before a take count as one.
    virtual void give(Signal signal) = 0;
    /// Clears a give no one took.
    virtual void drop(Signal signal) = 0;
    /// Loop only: blocks until `signal` is given or `timeout_ms` passes.
    virtual bool take(Signal signal, uint32_t timeout_ms) = 0;
    /// Microseconds, on the clock the interrupts stamp with (esp_timer_get_time).
    virtual uint64_t now() const = 0;
};

class Scan {
  public:
    explicit Scan(Panel& panel) : panel_(panel) {}

    /// Checks the config and starts the panel. False, and the panel untouched, for a bounce size that isn't an even
    /// number of chunks a frame (an odd count makes the copy refill the buffer going out: #635's banding).
    bool start(const Config& config);
    /// One scan-out, and a bounce chunk's deadline (0 without bounce buffers).
    uint32_t frame_us() const { return frame_us_; }
    uint32_t copy_budget_us() const { return copy_budget_us_; }

    /// The panel's interrupts: stamp and count only.
    void vsync(uint64_t now_us);
    void frame_complete(uint64_t now_us);

  private:
    Panel& panel_;
    Config config_{};
    uint32_t frame_us_ = 0;
    uint32_t copy_budget_us_ = 0;
};

}  // namespace panel_scan
