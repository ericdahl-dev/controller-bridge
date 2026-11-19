// The capability question (#456): the unit answers with the protocol version both sides speak, in any mode.
#include "harness.h"
#include <string.h>

static dfw_unit unit;
static recording rec;

static int replied(const char *hex) {
    uint8_t want[64];
    size_t n = parse_hex(hex, want, sizeof want);
    return rec.sends == 1 && rec.sent_length == n && memcmp(rec.sent, want, n) == 0;
}

void a_capability_ask_gets_the_answer(void) {
    fresh(&unit, &rec);
    feed(&unit, "F0 00 02 0B 7F 10 20 00 02 00 01 F7");
    dfw_tick(&unit, 0);
    CHECK(replied("F0 00 02 0B 01 10 20 00 02 00 01 F7"));
}

void a_newer_host_gets_our_version(void) {
    fresh(&unit, &rec);
    feed(&unit, "F0 00 02 0B 7F 10 20 00 02 00 05 F7");
    dfw_tick(&unit, 0);
    CHECK(replied("F0 00 02 0B 01 10 20 00 02 00 01 F7"));
}

void a_capability_ask_with_version_0_gets_no_answer(void) {
    fresh(&unit, &rec);
    feed(&unit, "F0 00 02 0B 7F 10 20 00 02 00 00 F7");
    dfw_tick(&unit, 0);
    CHECK(rec.sends == 0);
}
