// The panel's receive path (#620). The loop task polls the UDP socket and hands each datagram to the core, so the core
// only ever runs on that one task (it isn't thread-safe). lwIP's socket buffer is the queue: in a burst, the newest
// datagrams may be dropped there, which is fine, since the feed sends changes and a full snapshot every 2 s (#617).
#pragma once

#include <cstddef>
#include <cstdint>

#include "deck_core.h"

namespace feed_drain {

/// The biggest datagram read: one UDP payload in an Ethernet frame (1500 less the IP and UDP headers). The feed's
/// bundles (#636) are about 700 B and split past 1200 B. Bigger ones are dropped. A fixed buffer, read into per frame.
constexpr size_t kMaxDatagram = 1472;
/// At most this many datagrams a frame, so a burst can't hold the screen up; the rest wait for the next frame.
constexpr int kPerFrame = 16;

/// A UDP socket, as the board layer has it (WiFiUDP).
struct Socket {
    virtual ~Socket() = default;
    /// The next waiting datagram's size; 0 if none.
    virtual size_t next_size() = 0;
    /// Reads the next datagram into `into`; returns its length.
    virtual size_t read(uint8_t* into, size_t room) = 0;
    /// Drops the next datagram unread.
    virtual void skip() = 0;
};

class Drain {
public:
    /// Feeds waiting datagrams to `core`, stamped `now_ms`; returns how many were read.
    int run(Socket& socket, deck_core::DeckCore& core, uint32_t now_ms);
    /// Datagrams dropped for being bigger than kMaxDatagram.
    uint32_t too_big() const { return too_big_; }

private:
    uint8_t buffer_[kMaxDatagram];
    uint32_t too_big_ = 0;
};

}  // namespace feed_drain
