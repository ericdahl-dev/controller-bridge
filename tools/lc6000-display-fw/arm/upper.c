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

void upper_start(upper_progress *progress, const uint8_t *b) {
    progress->status = UPPER_BAD;
    progress->entry = 0;
    if (word(b) != UPPER_MARKER || word(b + 4) != UPPER_VERSION) return;
    progress->length = word(b + 8);
    if (progress->length < UPPER_HEADER || progress->length > UPPER_LIMIT) return;
    progress->done = 16;
    progress->crc = 0xFFFFFFFFu;
    progress->status = UPPER_CHECKING;
}

uint8_t upper_step(upper_progress *progress, const uint8_t *b, uint32_t budget) {
    if (progress->status != UPPER_CHECKING) return progress->status;
    uint32_t end = progress->length - progress->done > budget ? progress->done + budget : progress->length;
    uint32_t crc = progress->crc;
    for (uint32_t i = progress->done; i < end; i++) {
        crc ^= b[i];
        crc = (crc >> 4) ^ nibbles[crc & 15u];
        crc = (crc >> 4) ^ nibbles[crc & 15u];
    }
    progress->crc = crc;
    progress->done = end;
    if (end < progress->length) return UPPER_CHECKING;
    uint32_t draw = word(b + 16);
    // The CRC, then Thumb code (bit 0 set) past the header and before B's end.
    if (~crc != word(b + 12) || !(draw & 1u) || draw < UPPER_BASE + UPPER_HEADER || draw >= UPPER_BASE + end) {
        progress->status = UPPER_BAD;
    } else {
        progress->entry = draw;
        progress->status = UPPER_GOOD;
    }
    return progress->status;
}

uint32_t upper_check(const uint8_t *b) {
    upper_progress progress;
    upper_start(&progress, b);
    upper_step(&progress, b, UPPER_LIMIT);
    return progress.entry;
}
