#include "frame_ledger.h"

namespace frame_ledger {

void Ledger::read(uint32_t us) {
    waiting_ = true;
    waiting_us_ = us;
}

void Ledger::swapped(uint32_t) {
    if (!waiting_) return;
    waiting_ = false;
    in_flight_ = true;
    in_flight_us_ = waiting_us_;
}

void Ledger::on_glass(uint32_t us) {
    if (!in_flight_) return;
    in_flight_ = false;
    const uint32_t lag = us - in_flight_us_;
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
