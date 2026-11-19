#include "upper.h"

static uint32_t word(const uint8_t *at) {
    return (uint32_t)at[0] | (uint32_t)at[1] << 8 | (uint32_t)at[2] << 16 | (uint32_t)at[3] << 24;
}

/// zlib's CRC-32, a bit at a time: no table, so it stays small in block A.
static uint32_t crc32(const uint8_t *bytes, uint32_t length) {
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < length; i++) {
        crc ^= bytes[i];
        for (int bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

uint32_t upper_check(const uint8_t *b) {
    if (word(b) != UPPER_MARKER) return 0;
    if (word(b + 4) != UPPER_VERSION) return 0;
    uint32_t length = word(b + 8);
    if (length < UPPER_HEADER || length > UPPER_LIMIT) return 0;
    if (crc32(b + 16, length - 16) != word(b + 12)) return 0;
    uint32_t draw = word(b + 16);
    // Thumb code (bit 0 set) past the header and before B's end.
    if (!(draw & 1u) || draw < UPPER_BASE + UPPER_HEADER || draw >= UPPER_BASE + length) return 0;
    return draw;
}
