#include "dfw.h"

#include <string.h>

/// inMusic's SysEx header from the host to the unit, then our command (#456). 0x20 is a placeholder until #466.
static const uint8_t host_header[] = { 0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10 };
#define DFW_CMD 0x20
/// The protocol version this code speaks.
#define DFW_VERSION 1
enum { OP_CAPABILITY = 0x00, OP_BEGIN = 0x01, OP_END = 0x02, OP_DECK = 0x03, OP_TEXT = 0x04, OP_TEMPO = 0x05,
       OP_STATE = 0x07, OP_BEAT = 0x08, OP_NEEDLE = 0x09 };
/// A text escape: the next byte plus 0x80 is the Windows-1252 code.
#define TEXT_ESCAPE 0x7F
/// Bit 6 of the state flags is reserved: a message with it set is malformed.
#define STATE_RESERVED 0x40
/// Bit 5 of the state flags: Syndicate's feedback has stopped.
#define FLAG_STALE 0x20
/// No drawn-display message for this long draws the waiting look (#464): three missed heartbeats.
#define SILENCE_MS 3000u

void dfw_init(dfw_unit *unit, const dfw_port *port, dfw_pixel *frame, const dfw_drawing *drawing) {
    memset(unit, 0, sizeof *unit);
    unit->port = *port;
    unit->frame = frame;
    unit->drawing = drawing;
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
    case OP_CAPABILITY: case OP_BEGIN: case OP_END: case OP_STATE: case OP_BEAT: return 2;
    case OP_NEEDLE: case OP_TEMPO: return 3;
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
    case OP_BEAT:
        return args[0] <= 4;
    case OP_NEEDLE: case OP_TEMPO:
        return 1;   // any two 7-bit bytes are an angle, or a tempo
    default:
        return 0;
    }
}

/// Decodes a text message's characters into Windows-1252 codes; -1 if any is malformed: a code below 0x20, an escape
/// with nothing after it, or one of Windows-1252's undefined codes other than 0x81 (the box).
static int decode_text(const uint8_t *chars, size_t count, uint8_t *codes) {
    int n = 0;
    for (size_t i = 0; i < count; i++) {
        uint8_t code = chars[i];
        if (code == TEXT_ESCAPE) {
            if (++i == count) return -1;
            code = (uint8_t)(0x80 | chars[i]);
            if (code == 0x8D || code == 0x8F || code == 0x90 || code == 0x9D) return -1;
        } else if (code < 0x20) {
            return -1;
        }
        codes[n++] = code;
    }
    return n;
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
    if (length != header + 4 + declared) return;
    const uint8_t *args = body + 1;
    // Text alone has no one length: its field and up to DFW_TEXT_MAX bytes of characters.
    uint8_t codes[DFW_TEXT_MAX];
    int code_count = 0;
    if (op == OP_TEXT) {
        if (declared < 2 || declared > 2 + DFW_TEXT_MAX || args[0] >= DFW_TEXT_FIELDS) return;
        code_count = decode_text(args + 1, declared - 2, codes);
        if (code_count < 0) return;
    } else if (declared == 0 || declared != op_length(op) || !in_range(op, args)) {
        return;
    }
    // One of ours: it counts as hearing from the host, and ends any silence.
    unit->heard = now_ms;
    if (unit->silent) {
        unit->silent = 0;
        unit->dirty = 1;
    }
    switch (op) {
    case OP_CAPABILITY:
        // No back buffer or no drawing means we can't draw: no answer, so the app falls back to images.
        if (unit->frame && unit->drawing) {
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
        unit->beat = 0;
        unit->needle = 0;
        unit->needle_heard = 0;
        break;
    case OP_DECK: {
        if (!unit->drawn) break;
        dfw_deck_state deck = { args[0], (uint8_t)channel(args + 1), (uint8_t)channel(args + 3),
                                (uint8_t)channel(args + 5), args[7] };
        // The heartbeat's deck, unchanged, changes nothing: its flags stay and nothing is redrawn (#459).
        if (memcmp(&deck, &unit->deck, sizeof deck) == 0) break;
        unit->deck = deck;
        // A new deck's play flags wait for its own state message (#464); only feedback stale carries over.
        unit->flags &= FLAG_STALE;
        unit->dirty = 1;
        break;
    }
    case OP_TEXT:
        if (!unit->drawn) break;
        memcpy(unit->text[args[0]], codes, (size_t)code_count);
        unit->text_length[args[0]] = (uint8_t)code_count;
        unit->dirty = 1;
        break;
    case OP_TEMPO:
        if (!unit->drawn) break;
        unit->tempo = (uint16_t)((args[0] << 7) | args[1]);
        unit->dirty = 1;
        break;
    case OP_STATE:
        if (!unit->drawn || unit->flags == args[0]) break;
        unit->flags = args[0];
        unit->dirty = 1;
        break;
    case OP_BEAT:
        if (!unit->drawn || unit->beat == args[0]) break;
        unit->beat = args[0];
        unit->dirty = 1;
        break;
    case OP_NEEDLE: {
        uint16_t angle = (uint16_t)((args[0] << 7) | args[1]);
        // The first one draws the marker, whatever its angle; after that, only a change.
        if (!unit->drawn || (unit->needle_heard && unit->needle == angle)) break;
        unit->needle = angle;
        unit->needle_heard = 1;
        unit->dirty = 1;
        break;
    }
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
    if (!unit->dirty || !unit->frame || !unit->drawing || !unit->drawn || unit->deck.number == 0) return;
    unit->dirty = 0;
    unit->now_ms = now_ms;
    unit->drawing->draw(unit->frame, unit);
    unit->port.present(unit->port.ctx, unit->frame);
}
