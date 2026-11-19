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
#define METER_64_90 "F0 00 02 0B 7F 10 20 00 03 0A 40 5A F7"

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
    feed(&unit, METER_64_90);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 1);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit, 500);   // the deck and its state may land in different ticks
    CHECK(unit.flags == 0x3F);
    feed(&unit, STATE_ALL);
    feed(&unit, BEAT_2);
    feed(&unit, NEEDLE_4096);
    feed(&unit, METER_64_90);
    dfw_tick(&unit, 1000);
    CHECK(rec.presents == 1);
    CHECK(unit.flags == 0x3F);
}

#define DECK_4_BLUE_EMPTY "F0 00 02 0B 7F 10 20 00 09 03 04 00 00 01 00 01 7F 00 F7"
#define METER_0_0 "F0 00 02 0B 7F 10 20 00 03 0A 00 00 F7"

/// Begin and deck 4, drawn once.
static void drawing_deck_4(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_4_BLUE_EMPTY);
    dfw_tick(&unit, 0);
}

/// The meter (#461): the first meter message draws it even at silence, the values a fresh unit holds, since until one
/// comes there is no meter at all.
void the_first_meter_at_silence_presents(void) {
    drawing_deck_4();
    CHECK(rec.presents == 1);
    feed(&unit, METER_0_0);
    dfw_tick(&unit, 10);
    CHECK(rec.presents == 2);
}

void a_changed_meter_presents(void) {
    drawing_deck_4();
    feed(&unit, METER_0_0);
    dfw_tick(&unit, 10);
    feed(&unit, METER_64_90);
    dfw_tick(&unit, 20);
    CHECK(rec.presents == 3);
}

void the_same_meter_does_not_present_again(void) {
    drawing_deck_4();
    feed(&unit, METER_64_90);
    dfw_tick(&unit, 10);
    feed(&unit, METER_64_90);
    dfw_tick(&unit, 20);
    CHECK(rec.presents == 2);
}

/// End forgets the meter: after a new begin, the first meter message draws it again, even at silence.
void end_forgets_the_meter(void) {
    drawing_deck_4();
    feed(&unit, METER_0_0);
    dfw_tick(&unit, 10);
    feed(&unit, "F0 00 02 0B 7F 10 20 00 02 02 01 F7");
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_4_BLUE_EMPTY);
    dfw_tick(&unit, 20);
    CHECK(rec.presents == 3);
    feed(&unit, METER_0_0);
    dfw_tick(&unit, 30);
    CHECK(rec.presents == 4);
}
