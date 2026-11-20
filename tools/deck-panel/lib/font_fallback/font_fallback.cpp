#include "font_fallback.h"

#include <cstdint>
#include <cstring>

namespace font_fallback {

namespace {

/// U+00C0 to U+00FF, Latin-1's letters, without their accents; "?" for the signs among them (× ÷) and þ Þ.
const char* const kLatin1[64] = {
    "A", "A", "A", "A", "A", "A", "AE", "C", "E", "E", "E", "E", "I", "I", "I", "I",   // C0-CF
    "D", "N", "O", "O", "O", "O", "O", "?", "O", "U", "U", "U", "U", "Y", "?", "ss",   // D0-DF
    "a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i",   // E0-EF
    "d", "n", "o", "o", "o", "o", "o", "?", "o", "u", "u", "u", "u", "y", "?", "y",   // F0-FF
};

/// The next character of valid UTF-8 at `p`: its code point, and how many bytes it took.
uint32_t next(const char* p, size_t& bytes) {
    const auto lead = static_cast<uint8_t>(p[0]);
    if (lead < 0x80) {
        bytes = 1;
        return lead;
    }
    bytes = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2;
    uint32_t code = lead & (0x3F >> (bytes - 1));
    for (size_t i = 1; i < bytes; ++i) code = code << 6 | (static_cast<uint8_t>(p[i]) & 0x3F);
    return code;
}

}  // namespace

void fit(const char* text, char* out, size_t size) {
    if (size == 0) return;
    size_t n = 0;
    char ascii[2] = {0, 0};
    for (const char* p = text; *p;) {
        size_t bytes;
        const uint32_t code = next(p, bytes);
        p += bytes;
        const char* shown;
        if (code >= 0x20 && code < 0x7F) {
            ascii[0] = static_cast<char>(code);
            shown = ascii;
        } else if (code >= 0xC0 && code <= 0xFF) {
            shown = kLatin1[code - 0xC0];
        } else if (code == 0x2026) {
            shown = "...";
        } else {
            shown = "?";
        }
        const size_t length = std::strlen(shown);
        if (n + length > size - 1) break;  // whole or not at all
        std::memcpy(out + n, shown, length);
        n += length;
    }
    out[n] = 0;
}

}  // namespace font_fallback
