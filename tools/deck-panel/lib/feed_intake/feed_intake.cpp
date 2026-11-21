#include "feed_intake.h"

#include <cstring>

namespace feed_intake {

bool Intake::push(const uint8_t* bytes, size_t length, uint64_t at_us) {
    Slot& slot = slots_[tail_ % kSlots];
    std::memcpy(slot.bytes, bytes, length);
    slot.length = length;
    slot.at_us = at_us;
    ++tail_;
    return true;
}

int Intake::drain(deck_core::DeckCore& core) {
    int fed = 0;
    while (head_ != tail_) {
        const Slot& slot = slots_[head_ % kSlots];
        core.feed(slot.bytes, slot.length, static_cast<uint32_t>(slot.at_us / 1000));
        ++head_;
        ++fed;
    }
    return fed;
}

}  // namespace feed_intake
