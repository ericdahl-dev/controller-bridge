// The feed's intake (#664): each datagram is stamped when it arrives and queued in fixed memory; the loop's frame takes
// what came since the last one and feeds the core each datagram at its own arrival time.
#pragma once

#include <cstddef>
#include <cstdint>

#include "deck_core.h"

namespace feed_intake {

/// The biggest datagram kept: one UDP payload in an Ethernet frame (1500 less the IP and UDP headers).
constexpr size_t kMaxDatagram = 1472;
/// Datagrams held between frames.
constexpr size_t kSlots = 8;

class Intake {
public:
    /// Queues a datagram that arrived at `at_us` (microseconds, esp_timer's clock). False if it wasn't kept.
    bool push(const uint8_t* bytes, size_t length, uint64_t at_us);
    /// Feeds the core every datagram queued, oldest first, each at its arrival (in ms, millis' clock); returns how many.
    int drain(deck_core::DeckCore& core);

private:
    struct Slot {
        uint64_t at_us = 0;
        size_t length = 0;
        uint8_t bytes[kMaxDatagram];
    };
    Slot slots_[kSlots];
    size_t head_ = 0;  // the next to drain
    size_t tail_ = 0;  // the next to fill
};

}  // namespace feed_intake
