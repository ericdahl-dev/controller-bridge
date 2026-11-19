#include "dfw.h"
#include "draw.h"

#include <string.h>

/// inMusic's SysEx header from the host to the unit, then our command (#456). 0x20 is a placeholder until #466.
static const uint8_t host_header[] = { 0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10 };
#define DFW_CMD 0x20
/// The protocol version this code speaks.
#define DFW_VERSION 1
enum { OP_CAPABILITY = 0x00, OP_BEGIN = 0x01, OP_END = 0x02, OP_DECK = 0x03, OP_STATE = 0x07 };
/// Bit 6 of the state flags is reserved: a message with it set is malformed.
#define STATE_RESERVED 0x40
/// Bit 5 of the state flags: Syndicate's feedback has stopped.
#define FLAG_STALE 0x20
/// No drawn-display message for this long draws the waiting look (#464): three missed heartbeats.
#define SILENCE_MS 3000u

void dfw_init(dfw_unit *unit, const dfw_port *port, dfw_pixel *frame) {
    memset(unit, 0, sizeof *unit);
    unit->port = *port;
    unit->frame = frame;
}

void dfw_set_frame(dfw_unit *unit, dfw_pixel *frame) { unit->frame = frame; }

void dfw_message(dfw_unit *unit, const uint8_t *bytes, size_t length) {
    uint8_t next = (uint8_t)((unit->head + 1) % DFW_INBOX);
    if (length > DFW_MESSAGE_MAX || next == unit->tail) return;
    dfw_slot *slot = &unit->inbox[unit->head];
    memcpy(slot->bytes, bytes, length);
    slot->length = (uint8_t)length;
    unit->head = next;
}

/// Each op's one exact length, counting the op itself; 0 for an op this version doesn't take.
static uint8_t op_length(uint8_t op) {
    switch (op) {
    case OP_CAPABILITY: case OP_BEGIN: case OP_END: case OP_STATE: return 2;
    case OP_DECK: return 9;
    default: return 0;
    }
}

/// A color channel sent as two 7-bit bytes, high then low; -1 if it's over 255.
static int channel(const uint8_t *two) { return two[0] > 1 ? -1 : (two[0] << 7) | two[1]; }

/// Whether an op's arguments are in range: versions are never 0, a deck is 1-4 with channels up to 255 and a known
/// player, and a state's reserved bit is clear.
static int in_range(uint8_t op, const uint8_t *args) {
    switch (op) {
    case OP_CAPABILITY: case OP_BEGIN: case OP_END:
        return args[0] != 0;
    case OP_DECK:
        return args[0] >= 1 && args[0] <= 4 && channel(args + 1) >= 0 && channel(args + 3) >= 0 &&
               channel(args + 5) >= 0 && args[7] <= 5;
    case OP_STATE:
        return !(args[0] & STATE_RESERVED);
    default:
        return 0;
    }
}

static void act(dfw_unit *unit, const uint8_t *bytes, size_t length, uint32_t now_ms) {
    size_t header = sizeof host_header;
    // header, cmd, two length bytes, the op and its args, F7
    if (length < header + 5 || memcmp(bytes, host_header, header) != 0 || bytes[header] != DFW_CMD) return;
    if (bytes[length - 1] != 0xF7) return;
    for (size_t i = 1; i < length - 1; i++) if (bytes[i] & 0x80) return;
    size_t declared = ((size_t)bytes[header + 1] << 7) | bytes[header + 2];
    const uint8_t *body = bytes + header + 3;
    uint8_t op = body[0];
    if (declared == 0 || declared != op_length(op) || length != header + 4 + declared) return;
    const uint8_t *args = body + 1;
    if (!in_range(op, args)) return;
    // One of ours: it counts as hearing from the host, and ends any silence.
    unit->heard = now_ms;
    if (unit->silent) {
        unit->silent = 0;
        unit->dirty = 1;
    }
    switch (op) {
    case OP_CAPABILITY:
        // No back buffer means we can't draw: no answer, so the app falls back to images.
        if (unit->frame) {
            // The reply header (as the unit's acks), then the version both sides speak.
            const uint8_t answer[] = { 0xF0, 0x00, 0x02, 0x0B, 0x01, 0x10, DFW_CMD, 0x00, 0x02, OP_CAPABILITY,
                                       args[0] < DFW_VERSION ? args[0] : DFW_VERSION, 0xF7 };
            unit->port.send(unit->port.ctx, answer, sizeof answer);
        }
        break;
    case OP_BEGIN:
        unit->drawn = 1;
        break;
    case OP_END:
        // Back to image mode: nothing waiting is drawn, and the deck is forgotten, so a later begin waits for a
        // new one rather than redrawing this.
        unit->drawn = 0;
        unit->dirty = 0;
        unit->deck = (dfw_deck_state){ 0, 0, 0, 0, 0 };
        unit->flags = 0;
        break;
    case OP_DECK:
        if (!unit->drawn) break;
        unit->deck = (dfw_deck_state){ args[0], (uint8_t)channel(args + 1), (uint8_t)channel(args + 3),
                                       (uint8_t)channel(args + 5), args[7] };
        // A new deck's play flags wait for its own state message (#464); only feedback stale carries over.
        unit->flags &= FLAG_STALE;
        unit->dirty = 1;
        break;
    case OP_STATE:
        if (!unit->drawn) break;
        unit->flags = args[0];
        unit->dirty = 1;
        break;
    default:
        break;
    }
}

int dfw_stale(const dfw_unit *unit) { return unit->silent || (unit->flags & FLAG_STALE); }

void dfw_tick(dfw_unit *unit, uint32_t now_ms) {
    while (unit->tail != unit->head) {
        dfw_slot *slot = &unit->inbox[unit->tail];
        act(unit, slot->bytes, slot->length, now_ms);
        unit->tail = (uint8_t)((unit->tail + 1) % DFW_INBOX);
    }
    // Unsigned subtraction, so the clock wrapping isn't silence.
    if (unit->drawn && !unit->silent && now_ms - unit->heard >= SILENCE_MS) {
        unit->silent = 1;
        unit->dirty = 1;
    }
    // Only drawn mode draws, and only once a deck is known.
    if (!unit->dirty || !unit->frame || !unit->drawn || unit->deck.number == 0) return;
    unit->dirty = 0;
    dfw_draw(unit->frame, &unit->deck);
    unit->port.present(unit->port.ctx, unit->frame);
}
