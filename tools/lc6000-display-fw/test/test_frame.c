// The back buffer arrives late (#466, #467): the hook starts the unit on our first message and hands in an SDRAM
// frame only when it has one. Without a frame nothing is drawn, and the capability ask gets no answer, so the app
// times out and falls back to images (#456).
#include "harness.h"

#define CAPABILITY_V1 "F0 00 02 0B 7F 10 20 00 02 00 01 F7"
#define BEGIN_V1 "F0 00 02 0B 7F 10 20 00 02 01 01 F7"
#define DECK_2_RED_TRACK "F0 00 02 0B 7F 10 20 00 09 03 02 01 7F 00 00 00 00 01 F7"

static dfw_unit unit;
static recording rec;
static dfw_pixel late[DFW_SIZE * DFW_SIZE];

void with_no_frame_nothing_is_drawn(void) {
    fresh_without_frame(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit);
    CHECK(rec.presents == 0);
}

void a_frame_handed_in_later_is_drawn(void) {
    fresh_without_frame(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit);
    dfw_set_frame(&unit, late);
    dfw_tick(&unit);
    CHECK(rec.presents == 1);
}

void with_no_frame_the_capability_ask_gets_no_answer(void) {
    fresh_without_frame(&unit, &rec);
    feed(&unit, CAPABILITY_V1);
    dfw_tick(&unit);
    CHECK(rec.sends == 0);
}
