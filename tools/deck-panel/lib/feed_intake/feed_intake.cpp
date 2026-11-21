#include "feed_intake.h"

#include <cstring>

namespace feed_intake {

bool Intake::push(const uint8_t* bytes, size_t length, uint64_t at_us) {
    if (length > kMaxDatagram) {
        ++too_big_;
        return false;
    }
    if (tail_ - head_ == kSlots) {
        ++dropped_;
        return false;
    }
    Slot& slot = slots_[tail_ % kSlots];
    std::memcpy(slot.bytes, bytes, length);
    slot.length = length;
    slot.at_us = at_us;
    ++tail_;
    return true;
}

Drained Intake::drain(deck_core::DeckCore& core) {
    Drained got;
    while (head_ != tail_) {
        const Slot& slot = slots_[head_ % kSlots];
        core.feed(slot.bytes, slot.length, static_cast<uint32_t>(slot.at_us / 1000));
        got.newest_us = slot.at_us;
        ++head_;
        ++got.count;
    }
    return got;
}

}  // namespace feed_intake
