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

static void act(dfw_unit *unit, const uint8_t *bytes, size_t length) {
    size_t header = sizeof host_header;
    if (length < header + 4 || memcmp(bytes, host_header, header) != 0 || bytes[header] != DFW_CMD) return;
    uint8_t op = bytes[header + 3];
    if (op == OP_BEGIN) unit->drawn = 1;
    if (op == OP_END) unit->drawn = 0;
    if (op == OP_DECK && unit->drawn) unit->dirty = 1;
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
