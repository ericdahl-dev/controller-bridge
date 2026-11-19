// frame-dump <message hex>... (#515): the frame the native build draws for these messages, as the emulated chip gets
// them (each copied in, then one draw tick at time 0), written to stdout as 198x198 little-endian 0x00RRGGBB words.
// arm/test/test_block.py compares it with the frame blocks A and B draw under emulation.
#include "dfw.h"
#include "draw.h"
#include <stdio.h>
#include <stdlib.h>

static void present(void *ctx, const dfw_pixel *frame) { (void)ctx; (void)frame; }
static void send(void *ctx, const uint8_t *bytes, size_t length) { (void)ctx; (void)bytes; (void)length; }

static dfw_pixel frame[DFW_SIZE * DFW_SIZE];
static dfw_unit unit;

int main(int argc, char **argv) {
    dfw_port port = { present, send, 0 };
    dfw_init(&unit, &port, frame, &dfw_drawn);
    for (int i = 1; i < argc; i++) {
        uint8_t bytes[DFW_MESSAGE_MAX];
        size_t length = 0;
        for (const char *h = argv[i]; h[0] && h[1] && length < sizeof bytes; h += 2) {
            char pair[3] = { h[0], h[1], 0 };
            bytes[length++] = (uint8_t)strtoul(pair, 0, 16);
        }
        dfw_message(&unit, bytes, length);
    }
    dfw_tick(&unit, 0);
    for (size_t i = 0; i < DFW_SIZE * DFW_SIZE; i++) {
        uint8_t le[4] = { (uint8_t)frame[i], (uint8_t)(frame[i] >> 8), (uint8_t)(frame[i] >> 16), (uint8_t)(frame[i] >> 24) };
        fwrite(le, 1, 4, stdout);
    }
    return 0;
}
