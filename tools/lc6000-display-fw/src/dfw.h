// The drawn jog display (#455): message bytes in, a drawn frame out. Called only from the stock image's hook: one
// call per display message, and a periodic draw tick. No allocation; the frame is a fixed back buffer
// the caller hands in.
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
    /// A reply to the host, F0 through F7 (on the unit: the stock ack sender, on WD's cable).
    void (*send)(void *ctx, const uint8_t *bytes, size_t length);
    void *ctx;
} dfw_port;

/// The longest message kept: the longest valid one (deck, 19 bytes) with room to spare. Longer ones are dropped.
#define DFW_MESSAGE_MAX 32
/// Messages waiting for the next tick. The hook copies them in as the stock parser dispatches them (main loop, #466),
/// never keeping a pointer into the stock SysEx buffer; the tick acts on them.
#define DFW_INBOX 16

typedef struct {
    uint8_t length;
    uint8_t bytes[DFW_MESSAGE_MAX];
} dfw_slot;

/// The deck in front, as the deck message gave it.
typedef struct { uint8_t number, r, g, b, player; } dfw_deck_state;

typedef struct {
    dfw_port port;
    volatile uint8_t head, tail;
    dfw_slot inbox[DFW_INBOX];
    uint8_t drawn;
    dfw_deck_state deck;
    /// The state message's flags: bit 0 loaded, 1 playing, 2 play pending, 3 cue held, 4 loop on, 5 feedback stale.
    uint8_t flags;
    /// When the last of our messages came, and whether 3 s have passed since (the waiting look).
    uint32_t heard;
    uint8_t silent;
    uint8_t dirty;
    /// The back buffer, DFW_SIZE * DFW_SIZE pixels, owned by the caller: on the unit it lives in SDRAM (#466).
    dfw_pixel *frame;
} dfw_unit;

/// Starts the unit. `frame` may be NULL until the hook has one (see dfw_set_frame).
void dfw_init(dfw_unit *unit, const dfw_port *port, dfw_pixel *frame);
/// Hands in the back buffer. Until there is one, nothing is drawn and the capability ask gets no answer.
void dfw_set_frame(dfw_unit *unit, dfw_pixel *frame);
/// One whole display message, F0 through F7. Only copies it; the tick acts on it.
void dfw_message(dfw_unit *unit, const uint8_t *bytes, size_t length);
/// The draw tick: acts on the waiting messages, then presents a frame if something changed. `now_ms` is a
/// millisecond clock that may wrap (on the unit, the HAL tick).
void dfw_tick(dfw_unit *unit, uint32_t now_ms);
/// Whether the display shows the waiting look: the host says feedback stopped, or nothing came for 3 s.
int dfw_stale(const dfw_unit *unit);

#endif
