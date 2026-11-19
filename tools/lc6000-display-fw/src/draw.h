// The drawn display's picture (#457): design B as JogDisplayRenderer draws it, into a back buffer. No allocation, no
// libc beyond memcpy/memset, float math only (the chip is a Cortex-M4F).
#ifndef DFW_DRAW_H
#define DFW_DRAW_H
#include "dfw.h"

/// Writes all DFW_SIZE × DFW_SIZE pixels for `deck`, upright, top row first, as 0x00RRGGBB. A number outside 1-4 or an
/// unknown player still draws a whole frame.
void dfw_draw(dfw_pixel *frame, const dfw_deck_state *deck);

#endif
