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
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 1);
}

static void a_deck_before_begin_draws_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 0);
}

static void a_deck_after_end_draws_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, END_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 0);
}

void a_malformed_deck_is_ignored(void);
void a_malformed_begin_is_ignored(void);
void the_length_and_the_f7_are_checked_against_the_bytes_received(void);
void the_settings_flash_commands_are_never_acted_on(void);
void an_oversized_message_is_ignored(void);
void random_bytes_change_nothing(void);

void a_capability_ask_gets_the_answer(void);
void a_newer_host_gets_our_version(void);
void a_capability_ask_with_version_0_gets_no_answer(void);

void every_vector_decodes(void);
void every_invalid_vector_is_ignored(void);

void with_no_frame_nothing_is_drawn(void);
void a_frame_handed_in_after_end_draws_nothing(void);
void a_frame_handed_in_later_is_drawn(void);
void with_no_frame_the_capability_ask_gets_no_answer(void);

#define STATE_LOADED "F0 00 02 0B 7F 10 20 00 02 07 01 F7"

static void an_end_before_the_tick_draws_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    feed(&unit, END_V1);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 0);
}

static void a_state_before_any_deck_draws_nothing(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, STATE_LOADED);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 0);
}

static void a_second_begin_doesnt_redraw_the_old_deck(void) {
    fresh(&unit, &rec);
    feed(&unit, BEGIN_V1);
    feed(&unit, DECK_2_RED_TRACK);
    dfw_tick(&unit, 0);
    feed(&unit, END_V1);
    feed(&unit, BEGIN_V1);
    feed(&unit, STATE_LOADED);
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 1);
}

void the_state_flags_decode(void);
void a_state_with_the_reserved_bit_or_a_wrong_length_is_ignored(void);

void begin_while_drawing_changes_nothing(void);
void a_deck_clears_the_deck_flags_but_not_stale(void);

void three_seconds_of_silence_is_stale(void);
void any_message_clears_the_silence(void);
void garbage_doesnt_count_as_a_message(void);
void the_clock_wrapping_isnt_silence(void);
void the_stale_flag_is_stale_too(void);

const test_case all_tests[] = {
    { "begin then deck presents a frame", begin_then_deck_presents_a_frame },
    { "a deck before begin draws nothing", a_deck_before_begin_draws_nothing },
    { "a deck after end draws nothing", a_deck_after_end_draws_nothing },
    { "a malformed deck is ignored", a_malformed_deck_is_ignored },
    { "a malformed begin is ignored", a_malformed_begin_is_ignored },
    { "the length and the F7 are checked against the bytes received",
      the_length_and_the_f7_are_checked_against_the_bytes_received },
    { "the settings flash commands are never acted on", the_settings_flash_commands_are_never_acted_on },
    { "an oversized message is ignored", an_oversized_message_is_ignored },
    { "random bytes change nothing", random_bytes_change_nothing },
    { "a capability ask gets the answer", a_capability_ask_gets_the_answer },
    { "a newer host gets our version", a_newer_host_gets_our_version },
    { "a capability ask with version 0 gets no answer", a_capability_ask_with_version_0_gets_no_answer },
    { "every vector decodes", every_vector_decodes },
    { "every invalid vector is ignored", every_invalid_vector_is_ignored },
    { "with no frame nothing is drawn", with_no_frame_nothing_is_drawn },
    { "a frame handed in after end draws nothing", a_frame_handed_in_after_end_draws_nothing },
    { "a frame handed in later is drawn", a_frame_handed_in_later_is_drawn },
    { "with no frame the capability ask gets no answer", with_no_frame_the_capability_ask_gets_no_answer },
    { "an end before the tick draws nothing", an_end_before_the_tick_draws_nothing },
    { "a state before any deck draws nothing", a_state_before_any_deck_draws_nothing },
    { "a second begin doesn't redraw the old deck", a_second_begin_doesnt_redraw_the_old_deck },
    { "the state flags decode", the_state_flags_decode },
    { "a state with the reserved bit or a wrong length is ignored",
      a_state_with_the_reserved_bit_or_a_wrong_length_is_ignored },
    { "begin while drawing changes nothing", begin_while_drawing_changes_nothing },
    { "a deck clears the deck flags but not stale", a_deck_clears_the_deck_flags_but_not_stale },
    { "three seconds of silence is stale", three_seconds_of_silence_is_stale },
    { "any message clears the silence", any_message_clears_the_silence },
    { "garbage doesn't count as a message", garbage_doesnt_count_as_a_message },
    { "the clock wrapping isn't silence", the_clock_wrapping_isnt_silence },
    { "the stale flag is stale too", the_stale_flag_is_stale_too },
    { 0, 0 },
};
