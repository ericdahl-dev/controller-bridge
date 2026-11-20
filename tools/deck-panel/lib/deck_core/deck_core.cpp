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

/// Well-formed UTF-8: no stray, cut-short, overlong or surrogate sequences, nothing past U+10FFFF.
bool valid_utf8(const char* text) {
    const auto* p = reinterpret_cast<const uint8_t*>(text);
    while (*p) {
        uint8_t lead = *p++;
        int more;
        uint32_t code;
        if (lead < 0x80) continue;
        if (lead >= 0xC2 && lead <= 0xDF) { more = 1; code = lead & 0x1F; }
        else if (lead >= 0xE0 && lead <= 0xEF) { more = 2; code = lead & 0x0F; }
        else if (lead >= 0xF0 && lead <= 0xF4) { more = 3; code = lead & 0x07; }
        else return false;
        for (int i = 0; i < more; ++i, ++p) {
            if ((*p & 0xC0) != 0x80) return false;
            code = code << 6 | (*p & 0x3F);
        }
        if ((more == 2 && code < 0x800) || (more == 3 && code < 0x10000) || code > 0x10FFFF) return false;
        if (code >= 0xD800 && code <= 0xDFFF) return false;
    }
    return true;
}

bool parse(const uint8_t* bytes, size_t length, Message& out) {
    if (length % 4 != 0) return false;
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
            return valid_utf8(out.s);
        default:
            return false;
    }
}

/// The feed's addresses: one row each, its OSC type and what it sets (ADR 0011).
struct Row {
    const char* name;
    char type;
    /// Sets the value; false if it's out of range, which leaves the view as it was.
    bool (*apply)(DeckView&, const Message&);
};

const Row kRows[] = {
    {"deck", 'i',
     [](DeckView& v, const Message& m) {
         if (m.i < 1 || m.i > 4) return false;
         v.deck = m.i;
         return true;
     }},
    {"color", 'i',
     [](DeckView& v, const Message& m) {
         v.color = static_cast<uint32_t>(m.i) & 0xFFFFFF;
         return true;
     }},
    {"title", 's',
     [](DeckView& v, const Message& m) {
         v.title = m.s;
         return true;
     }},
    {"artist", 's',
     [](DeckView& v, const Message& m) {
         v.artist = m.s;
         return true;
     }},
};

}  // namespace

void DeckCore::feed(const uint8_t* bytes, size_t length, uint32_t) {
    Message message;
    if (!parse(bytes, length, message)) return;
    for (const Row& row : kRows) {
        if (row.type == message.type && std::strcmp(row.name, message.name) == 0) {
            if (row.apply(view_, message)) heard_ = true;
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
