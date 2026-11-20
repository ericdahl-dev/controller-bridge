#include "deck_core.h"

#include <cstring>

namespace deck_core {

namespace {

const char kPrefix[] = "/DeckBridge/Display/";

/// Reads a padded OSC string at `at`; returns its length, or -1 if it doesn't fit.
long read_string(const uint8_t* bytes, size_t length, size_t at) {
    for (size_t i = at; i < length; ++i) {
        if (bytes[i] == 0) return static_cast<long>(i - at);
    }
    return -1;
}

size_t padded(size_t n) { return (n + 4) & ~size_t(3); }

}  // namespace

void DeckCore::feed(const uint8_t* bytes, size_t length, uint32_t) {
    long address_length = read_string(bytes, length, 0);
    if (address_length < 0) return;
    const char* address = reinterpret_cast<const char*>(bytes);
    size_t at = padded(static_cast<size_t>(address_length));
    if (std::strncmp(address, kPrefix, sizeof kPrefix - 1) != 0) return;
    const char* name = address + sizeof kPrefix - 1;
    long tags_length = read_string(bytes, length, at);
    if (tags_length < 0) return;
    const char* tags = reinterpret_cast<const char*>(bytes + at);
    at += padded(static_cast<size_t>(tags_length));
    if (std::strcmp(tags, ",i") != 0 || at + 4 > length) return;
    int32_t value = static_cast<int32_t>(uint32_t(bytes[at]) << 24 | uint32_t(bytes[at + 1]) << 16 |
                                         uint32_t(bytes[at + 2]) << 8 | uint32_t(bytes[at + 3]));
    if (std::strcmp(name, "deck") == 0) {
        view_.deck = value;
        heard_ = true;
    }
}

void DeckCore::render(Screen& screen, uint32_t) {
    if (heard_) {
        screen.show_deck(view_);
    } else {
        screen.show_waiting();
    }
}

}  // namespace deck_core
