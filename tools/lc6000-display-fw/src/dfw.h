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

/// The most a text message carries (#458): 96 bytes of characters after escapes, so at most 96 characters.
#define DFW_TEXT_MAX 96
/// Text fields: title, artist, key, and the untitled words (player 5's own name).
#define DFW_TEXT_FIELDS 4
/// The longest message kept: the longest valid one (text, 108 bytes) with room to spare. Longer ones are dropped.
#define DFW_MESSAGE_MAX 112
/// Messages waiting for the next tick. The hook copies them in as the stock parser dispatches them (main loop, #466),
/// never keeping a pointer into the stock SysEx buffer; the tick acts on them.
#define DFW_INBOX 16

typedef struct {
    uint8_t length;
    uint8_t bytes[DFW_MESSAGE_MAX];
} dfw_slot;

struct dfw_unit;
/// The drawing, as a table of entry points: the protocol calls it only through this, so it can live in its own
/// block (#501). The hook passes NULL until it has a drawing it trusts; then nothing is drawn and the capability ask
/// gets no answer.
typedef struct {
    /// Writes all DFW_SIZE x DFW_SIZE pixels for the unit's deck in front.
    void (*draw)(dfw_pixel *frame, const struct dfw_unit *unit);
} dfw_drawing;

/// The deck in front, as the deck message gave it.
typedef struct { uint8_t number, r, g, b, player; } dfw_deck_state;

typedef struct dfw_unit {
    dfw_port port;
    const dfw_drawing *drawing;
    volatile uint8_t head, tail;
    dfw_slot inbox[DFW_INBOX];
    uint8_t drawn;
    dfw_deck_state deck;
    /// The state message's flags: bit 0 loaded, 1 playing, 2 play pending, 3 cue held, 4 loop on, 5 feedback stale.
    uint8_t flags;
    /// The master clock's beat, 1-4, or 0 with none (#459); the deck's needle, 0-16383 for a turn from 12 o'clock.
    uint8_t beat;
    uint16_t needle;
    /// The deck's mixer channel (#461): its level and the peak being held, 0-127.
    uint8_t level, peak;
    /// Whether a needle message has come since begin: until one does, no marker is drawn.
    uint8_t needle_heard;
    /// Whether a meter message has come since begin: until one does, no meter is drawn.
    uint8_t meter_heard;
    /// The texts as Windows-1252 codes (0x81 the box), and the tempo in tenths of a BPM, 0 for none (#458).
    uint8_t text[DFW_TEXT_FIELDS][DFW_TEXT_MAX];
    uint8_t text_length[DFW_TEXT_FIELDS];
    uint16_t tempo;
    /// Whether a text message has come since the deck last changed: until one has, no words are drawn (#458).
    uint8_t text_heard;
    /// When the last of our messages came, and whether 3 s have passed since (the waiting look).
    uint32_t heard;
    /// The clock at the tick that is drawing, for anything drawn over time.
    uint32_t now_ms;
    uint8_t silent;
    uint8_t dirty;
    /// The back buffer, DFW_SIZE * DFW_SIZE pixels, owned by the caller: on the unit it lives in SDRAM (#466).
    dfw_pixel *frame;
} dfw_unit;

/// Starts the unit. `frame` may be NULL until the hook has one (see dfw_set_frame); `drawing` is NULL when there is
/// none to call.
void dfw_init(dfw_unit *unit, const dfw_port *port, dfw_pixel *frame, const dfw_drawing *drawing);
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
