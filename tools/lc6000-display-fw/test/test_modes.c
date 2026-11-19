// Image mode and drawn mode (#455): the unit draws only between begin and end.
#include "harness.h"

#define BEGIN_V1 "F0 00 02 0B 7F 10 20 00 02 01 01 F7"
#define END_V1 "F0 00 02 0B 7F 10 20 00 02 02 01 F7"
#define DECK_2_RED_TRACK "F0 00 02 0B 7F 10 20 00 09 03 02 01 7F 00 00 00 00 01 F7"

static dfw_unit unit;
static recording rec;

static void begin_then_deck_presents_a_frame(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit);
    CHECK(rec.presents == 1);
}

static void a_deck_before_begin_draws_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit);
    CHECK(rec.presents == 0);
}

static void a_deck_after_end_draws_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, END_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit);
    CHECK(rec.presents == 0);
}

const test_case all_tests[] = {
    { "begin then deck presents a frame", begin_then_deck_presents_a_frame },
    { "a deck before begin draws nothing", a_deck_before_begin_draws_nothing },
    { "a deck after end draws nothing", a_deck_after_end_draws_nothing },
    { 0, 0 },
};
