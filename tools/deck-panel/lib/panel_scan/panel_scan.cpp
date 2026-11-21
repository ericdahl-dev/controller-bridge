#include "panel_scan.h"

#include "bounce_budget.h"

namespace panel_scan {

bool Scan::start(const Config& config) {
    const uint32_t frame_px = static_cast<uint32_t>(config.timing.width) * static_cast<uint32_t>(config.timing.height);
    if (config.bounce_px != 0 && (frame_px % config.bounce_px != 0 || (frame_px / config.bounce_px) % 2 != 0)) {
        return false;
    }
    if (!panel_.start(config)) return false;
    config_ = config;
    frame_us_ = frame_pacing::frame_us(config.timing);
    copy_budget_us_ = config.bounce_px == 0 ? 0 : bounce_budget::chunk_ns(config.timing, config.bounce_px) / 1000;
    return true;
}

bool Scan::present(bool last_area) {
    if (gate_.flush(last_area)) return true;
    panel_.hand_over();
    // A release left from a timed-out wait would free this swap before its latch: dropped before the gate is armed.
    panel_.drop(Signal::release);
    gate_.swapped();
    return false;
}

bool Scan::wait_release(uint32_t timeout_ms) {
    if (!gate_.must_wait()) return true;
    const bool got = panel_.take(Signal::release, timeout_ms);
    gate_.waited(got);
    return got;
}

void Scan::latch(uint64_t) {
    if (gate_.vsync()) panel_.give(Signal::release);
}

void Scan::vsync(uint64_t now_us) {
    if (config_.bounce_px == 0) latch(now_us);
}

void Scan::frame_complete(uint64_t now_us) {
    if (config_.bounce_px != 0) latch(now_us);
}

}  // namespace panel_scan
