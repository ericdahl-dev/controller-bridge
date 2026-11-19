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

void a_malformed_deck_is_ignored(void);
void a_malformed_begin_is_ignored(void);
void an_oversized_message_is_ignored(void);
void random_bytes_change_nothing(void);

void a_capability_ask_gets_the_answer(void);
void a_newer_host_gets_our_version(void);
void a_capability_ask_with_version_0_gets_no_answer(void);

const test_case all_tests[] = {
    { "begin then deck presents a frame", begin_then_deck_presents_a_frame },
    { "a deck before begin draws nothing", a_deck_before_begin_draws_nothing },
    { "a deck after end draws nothing", a_deck_after_end_draws_nothing },
    { "a malformed deck is ignored", a_malformed_deck_is_ignored },
    { "a malformed begin is ignored", a_malformed_begin_is_ignored },
    { "an oversized message is ignored", an_oversized_message_is_ignored },
    { "random bytes change nothing", random_bytes_change_nothing },
    { "a capability ask gets the answer", a_capability_ask_gets_the_answer },
    { "a newer host gets our version", a_newer_host_gets_our_version },
    { "a capability ask with version 0 gets no answer", a_capability_ask_with_version_0_gets_no_answer },
    { 0, 0 },
};
