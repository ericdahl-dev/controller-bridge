// The sequence rules (#464): the host re-sends begin, the deck and the state once a second while drawing.
#include "harness.h"

#define BEGIN_V1 "F0 00 02 0B 7F 10 20 00 02 01 01 F7"
#define DECK_2_RED_TRACK "F0 00 02 0B 7F 10 20 00 09 03 02 01 7F 00 00 00 00 01 F7"
#define STATE_ALL "F0 00 02 0B 7F 10 20 00 02 07 3F F7"

static dfw_unit unit;
static recording rec;

void begin_while_drawing_changes_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    feed(&unit, STATE_ALL);
    dfw_tick(&unit, 0);
    feed(&unit, BEGIN_V1);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 1);
    CHECK(unit.deck.number == 2);
    CHECK(unit.flags == 0x3F);
}

#define DECK_3_RED_TRACK "F0 00 02 0B 7F 10 20 00 09 03 03 01 7F 00 00 00 00 01 F7"
#define BEAT_2 "F0 00 02 0B 7F 10 20 00 02 08 02 F7"
#define NEEDLE_4096 "F0 00 02 0B 7F 10 20 00 03 09 20 00 F7"

void a_deck_clears_the_deck_flags_but_not_stale(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    feed(&unit, STATE_ALL);
    feed(&unit, DECK_3_RED_TRACK);
    dfw_tick(&unit, 0);
    CHECK(unit.flags == 0x20);
}

/// The heartbeat (#459, agent3's review): an unchanged deck keeps its flags, and a whole unchanged heartbeat presents
/// nothing, so the screen isn't redrawn once a second for nothing.
void an_unchanged_heartbeat_presents_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    feed(&unit, STATE_ALL);
    feed(&unit, BEAT_2);
    feed(&unit, NEEDLE_4096);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 1);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit, 500);   // the deck and its state may land in different ticks
    CHECK(unit.flags == 0x3F);
    feed(&unit, STATE_ALL);
    feed(&unit, BEAT_2);
    feed(&unit, NEEDLE_4096);
    dfw_tick(&unit, 1000);
    CHECK(rec.presents == 1);
    CHECK(unit.flags == 0x3F);
}
