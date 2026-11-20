#include "deck_core.h"

#include <cstring>

namespace deck_core {

namespace {

const char kPrefix[] = "/DeckBridge/Display/";

/// One OSC message with one value, as the feed sends (ADR 0011).
struct Message {
    const char* name = nullptr;  ///< the address after the prefix
    char type = 0;  ///< i, f or s
    int32_t i = 0;
    const char* s = nullptr;
};

/// Reads a padded OSC string at `at`; returns its length, or -1 if it doesn't fit.
long read_string(const uint8_t* bytes, size_t length, size_t at) {
    for (size_t i = at; i < length; ++i) {
        if (bytes[i] == 0) return static_cast<long>(i - at);
    }
    return -1;
}

size_t padded(size_t n) { return (n + 4) & ~size_t(3); }

bool parse(const uint8_t* bytes, size_t length, Message& out) {
    long address_length = read_string(bytes, length, 0);
    if (address_length < 0) return false;
    const char* address = reinterpret_cast<const char*>(bytes);
    if (std::strncmp(address, kPrefix, sizeof kPrefix - 1) != 0) return false;
    size_t at = padded(static_cast<size_t>(address_length));
    long tags_length = read_string(bytes, length, at);
    if (tags_length != 2 || bytes[at] != ',') return false;
    out.name = address + sizeof kPrefix - 1;
    out.type = static_cast<char>(bytes[at + 1]);
    at += padded(2);
    switch (out.type) {
        case 'i':
        case 'f':
            if (at + 4 > length) return false;
            out.i = static_cast<int32_t>(uint32_t(bytes[at]) << 24 | uint32_t(bytes[at + 1]) << 16 |
                                         uint32_t(bytes[at + 2]) << 8 | uint32_t(bytes[at + 3]));
            return true;
        case 's':
            if (read_string(bytes, length, at) < 0) return false;
            out.s = reinterpret_cast<const char*>(bytes + at);
            return true;
        default:
            return false;
    }
}

/// The feed's addresses: one row each, its OSC type and what it sets (ADR 0011).
struct Row {
    const char* name;
    char type;
    void (*apply)(DeckView&, const Message&);
};

const Row kRows[] = {
    {"deck", 'i', [](DeckView& v, const Message& m) { v.deck = m.i; }},
    {"color", 'i', [](DeckView& v, const Message& m) { v.color = static_cast<uint32_t>(m.i) & 0xFFFFFF; }},
    {"title", 's', [](DeckView& v, const Message& m) { v.title = m.s; }},
    {"artist", 's', [](DeckView& v, const Message& m) { v.artist = m.s; }},
};

}  // namespace

void DeckCore::feed(const uint8_t* bytes, size_t length, uint32_t) {
    Message message;
    if (!parse(bytes, length, message)) return;
    for (const Row& row : kRows) {
        if (row.type == message.type && std::strcmp(row.name, message.name) == 0) {
            row.apply(view_, message);
            heard_ = true;
        }
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
