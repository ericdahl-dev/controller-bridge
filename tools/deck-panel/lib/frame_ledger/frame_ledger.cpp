#include "frame_ledger.h"

namespace frame_ledger {

void Ledger::read(uint32_t us) {
    pending_ = true;
    pending_us_ = us;
}

void Ledger::swapped(uint32_t) {}

void Ledger::on_glass(uint32_t us) {
    if (!pending_) return;
    pending_ = false;
    const uint32_t lag = us - pending_us_;
    ++report_.frames;
    report_.lag_typical_us = lag;
    if (lag > report_.lag_worst_us) report_.lag_worst_us = lag;
}

Report Ledger::take() {
    const Report r = report_;
    report_ = {};
    return r;
}

}  // namespace frame_ledger
