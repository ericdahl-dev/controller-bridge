#include "upper.h"

static uint32_t word(const uint8_t *at) {
    return (uint32_t)at[0] | (uint32_t)at[1] << 8 | (uint32_t)at[2] << 16 | (uint32_t)at[3] << 24;
}

uint32_t upper_check(const uint8_t *b) {
    if (word(b) != UPPER_MARKER) return 0;
    return word(b + 16);
}
