// Block B's header (#501, upper.h), first in B at 0x08080000. Its length and CRC are 0 here: upper_seal.py fills
// them in from the built image, after the link.
#include "draw.h"
#include "upper.h"

typedef struct {
    uint32_t marker;
    uint32_t version;
    uint32_t length;
    uint32_t crc;
    uint32_t layout;
    void (*draw)(dfw_pixel *frame, const struct dfw_unit *unit);
    void (*band)(uint16_t *layer, const struct dfw_unit *unit);
} upper_header;

/// The ring in the band outside the frame (#524), drawn straight into layer 2 (320 x 240 RGB565).
void dfw_draw_band(uint16_t *layer, const dfw_unit *unit);

__attribute__((section(".upper_header"), used)) const upper_header upper_head = {
    UPPER_MARKER, UPPER_VERSION, 0, 0, DFW_LAYOUT, dfw_draw, dfw_draw_band,
};
