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

void Scan::vsync(uint64_t) {}

void Scan::frame_complete(uint64_t) {}

}  // namespace panel_scan
