#include "feed_drain.h"

namespace feed_drain {

int Drain::run(Socket& socket, deck_core::DeckCore& core, uint32_t now_ms) {
    int fed = 0;
    // Each turn takes one datagram, read or dropped, so a frame's work is bounded either way.
    for (int turn = 0; turn < kPerFrame; ++turn) {
        const size_t size = socket.next_size();
        if (size == 0) break;
        if (size > kMaxDatagram) {
            socket.skip();
            ++too_big_;
            continue;
        }
        const size_t length = socket.read(buffer_, sizeof buffer_);
        core.feed(buffer_, length, now_ms);
        ++fed;
    }
    return fed;
}

}  // namespace feed_drain
