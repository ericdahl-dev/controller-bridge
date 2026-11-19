#include "dfw.h"

#include <string.h>

/// inMusic's SysEx header from the host to the unit, then our command (#456). 0x20 is a placeholder until #466.
static const uint8_t host_header[] = { 0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10 };
#define DFW_CMD 0x20
enum { OP_CAPABILITY = 0x00, OP_BEGIN = 0x01, OP_END = 0x02, OP_DECK = 0x03 };

void dfw_init(dfw_unit *unit, const dfw_port *port) {
    memset(unit, 0, sizeof *unit);
    unit->port = *port;
}

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
    case OP_CAPABILITY: case OP_BEGIN: case OP_END: return 2;
    case OP_DECK: return 9;
    default: return 0;
    }
}

/// A color channel sent as two 7-bit bytes, high then low; -1 if it's over 255.
static int channel(const uint8_t *two) { return two[0] > 1 ? -1 : (two[0] << 7) | two[1]; }

static void act(dfw_unit *unit, const uint8_t *bytes, size_t length) {
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
    switch (op) {
    case OP_BEGIN:
        if (args[0] != 0) unit->drawn = 1;
        break;
    case OP_END:
        if (args[0] != 0) unit->drawn = 0;
        break;
    case OP_DECK: {
        int r = channel(args + 1), g = channel(args + 3), b = channel(args + 5);
        uint8_t number = args[0], player = args[7];
        if (number < 1 || number > 4 || r < 0 || g < 0 || b < 0 || player > 5 || !unit->drawn) break;
        unit->deck = (dfw_deck_state){ number, (uint8_t)r, (uint8_t)g, (uint8_t)b, player };
        unit->dirty = 1;
        break;
    }
    default:
        break;
    }
}

void dfw_tick(dfw_unit *unit) {
    while (unit->tail != unit->head) {
        dfw_slot *slot = &unit->inbox[unit->tail];
        act(unit, slot->bytes, slot->length);
        unit->tail = (uint8_t)((unit->tail + 1) % DFW_INBOX);
    }
    if (!unit->dirty) return;
    unit->dirty = 0;
    unit->port.present(unit->port.ctx, unit->frame);
}
