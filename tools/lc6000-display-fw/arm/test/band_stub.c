// A stand-in for agent1's dfw_draw_band (#524) until it lands in src/: the same signature, and one known pixel, so
// the block tests can see when block A calls B's band entry. Linked into block B only.
#include <stdint.h>

#include "dfw.h"

/// The pixel the stub writes: panel (0, 0), outside the frame and the band, magenta in RGB565.
#define BAND_STUB_PIXEL 0xF81Fu

void dfw_draw_band(uint16_t *layer, const dfw_unit *unit) {
    (void)unit;
    layer[0] = BAND_STUB_PIXEL;
}
