// The drawn jog display (#455): message bytes in, a drawn frame out. Called only from the stock image's hook: one
// call per display message, and a periodic draw tick. No allocation; the frame is a fixed back buffer.
#ifndef DFW_H
#define DFW_H
#include <stddef.h>
#include <stdint.h>

#define DFW_SIZE 198

/// One pixel of the back buffer. The panel's own format is the hook's business (#466/#467), not this code's.
typedef uint32_t dfw_pixel;

/// Where frames and replies go: the panel on the unit, a recording stub in the tests.
typedef struct {
    void (*present)(void *ctx, const dfw_pixel *frame);
    void *ctx;
} dfw_port;

/// The longest message kept: the longest valid one (deck, 19 bytes) with room to spare. Longer ones are dropped.
#define DFW_MESSAGE_MAX 32
/// Messages waiting for the next tick. The hook may run in the USB interrupt, so it only copies.
#define DFW_INBOX 16

typedef struct {
    uint8_t length;
    uint8_t bytes[DFW_MESSAGE_MAX];
} dfw_slot;

typedef struct {
    dfw_port port;
    volatile uint8_t head, tail;
    dfw_slot inbox[DFW_INBOX];
    uint8_t drawn;
    uint8_t dirty;
    dfw_pixel frame[DFW_SIZE * DFW_SIZE];
} dfw_unit;

void dfw_init(dfw_unit *unit, const dfw_port *port);
/// One whole display message, F0 through F7. Only copies it; the tick acts on it.
void dfw_message(dfw_unit *unit, const uint8_t *bytes, size_t length);
/// The draw tick: acts on the waiting messages, then presents a frame if something changed.
void dfw_tick(dfw_unit *unit);

#endif
