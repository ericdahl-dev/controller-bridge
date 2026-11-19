#include "upper.h"

static uint32_t word(const uint8_t *at) {
    return (uint32_t)at[0] | (uint32_t)at[1] << 8 | (uint32_t)at[2] << 16 | (uint32_t)at[3] << 24;
}

/// zlib's CRC-32 a nibble at a time: a 64-byte table, 11 instructions a byte on the M4 (a bit at a time is 54).
/// Never the chip's CRC unit: stock and its startup stage use it.
static const uint32_t nibbles[16] = {
    0x00000000u, 0x1DB71064u, 0x3B6E20C8u, 0x26D930ACu, 0x76DC4190u, 0x6B6B51F4u, 0x4DB26158u, 0x5005713Cu,
    0xEDB88320u, 0xF00F9344u, 0xD6D6A3E8u, 0xCB61B38Cu, 0x9B64C2B0u, 0x86D3D2D4u, 0xA00AE278u, 0xBDBDF21Cu,
};

uint32_t upper_check(const uint8_t *b, uint32_t layout) {
    if (word(b) != UPPER_MARKER || word(b + 4) != UPPER_VERSION) return 0;
    uint32_t length = word(b + 8);
    if (length < UPPER_HEADER || length > UPPER_LIMIT) return 0;
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 16; i < length; i++) {
        crc ^= b[i];
        crc = (crc >> 4) ^ nibbles[crc & 15u];
        crc = (crc >> 4) ^ nibbles[crc & 15u];
    }
    if (~crc != word(b + 12)) return 0;
    // B built against another dfw_unit would read A's state at the wrong offsets (#516).
    if (word(b + 16) != layout) return 0;
    uint32_t draw = word(b + 20);
    // Thumb code (bit 0 set) past the header and before B's end.
    if (!(draw & 1u) || draw < UPPER_BASE + UPPER_HEADER || draw >= UPPER_BASE + length) return 0;
    return draw;
}
