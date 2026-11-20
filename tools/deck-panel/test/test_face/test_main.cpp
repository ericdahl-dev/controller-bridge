// The deck screen's model (#621): what each widget shows, decided from the deck's state, so the board only draws.
#include <unity.h>

#include <cstring>
#include <initializer_list>

#include "deck_face.h"

void setUp() {}
void tearDown() {}

using deck_core::DeckView;
using deck_core::Face;

static DeckView loaded_deck() {
    DeckView v;
    v.deck = 1;
    v.color = 0xFF0000;
    v.loaded = true;
    std::strcpy(v.title, "Night Drive");
    std::strcpy(v.artist, "Example Artist");
    std::strcpy(v.key, "Am");
    v.bpm = 126;
    v.tempo = 0.8f;
    v.playing = v.sync = v.master = v.loop = true;
    v.loop_length = 0.5f;
    v.beat = 3;
    v.elapsed = 95;
    v.remaining = 212;
    v.progress = 0.3125f;
    v.phase = 0.5f;
    v.level = 0.75f;
    return v;
}

// An empty deck shows as empty: the deck number in its color and "No track loaded", every other widget blank or off.
void test_an_empty_deck_shows_no_track_loaded_and_nothing_else() {
    DeckView v = loaded_deck();
    v.loaded = false;
    const Face f = deck_core::face(v);
    TEST_ASSERT_EQUAL_STRING("1", f.deck);
    TEST_ASSERT_EQUAL_HEX32(0xFF0000, f.color);
    TEST_ASSERT_EQUAL_STRING("No track loaded", f.title);
    for (const char* text : {f.artist, f.key, f.bpm, f.tempo, f.elapsed, f.remaining, f.loop_length})
        TEST_ASSERT_EQUAL_STRING("", text);
    TEST_ASSERT_FALSE(f.playing || f.cue || f.sync || f.master || f.loop || f.end_warning || f.phase_shown);
    TEST_ASSERT_EQUAL(0, f.beat);
    TEST_ASSERT_EQUAL_FLOAT(0, f.progress);
    TEST_ASSERT_EQUAL_FLOAT(0, f.level);
}

void test_a_loaded_deck_shows_its_title_and_artist() {
    const Face f = deck_core::face(loaded_deck());
    TEST_ASSERT_EQUAL_STRING("Night Drive", f.title);
    TEST_ASSERT_EQUAL_STRING("Example Artist", f.artist);
    TEST_ASSERT_EQUAL_STRING("Am", f.key);
}

// BPM and tempo arrive at 2 decimals and show at 2, so the panel never rounds them differently from DeckBridge.
void test_bpm_and_tempo_show_at_2_decimals_tempo_signed() {
    DeckView v = loaded_deck();
    TEST_ASSERT_EQUAL_STRING("126.00", deck_core::face(v).bpm);
    TEST_ASSERT_EQUAL_STRING("+0.80%", deck_core::face(v).tempo);
    v.bpm = 174.25f;
    v.tempo = -2.5f;
    TEST_ASSERT_EQUAL_STRING("174.25", deck_core::face(v).bpm);
    TEST_ASSERT_EQUAL_STRING("-2.50%", deck_core::face(v).tempo);
    v.tempo = 0;
    TEST_ASSERT_EQUAL_STRING("0.00%", deck_core::face(v).tempo);
}

void test_an_unknown_bpm_shows_neither_bpm_nor_tempo() {
    DeckView v = loaded_deck();
    v.bpm = 0;
    TEST_ASSERT_EQUAL_STRING("", deck_core::face(v).bpm);
    TEST_ASSERT_EQUAL_STRING("", deck_core::face(v).tempo);
}

void test_times_show_as_minutes_and_seconds_remaining_with_a_minus() {
    DeckView v = loaded_deck();
    TEST_ASSERT_EQUAL_STRING("1:35", deck_core::face(v).elapsed);
    TEST_ASSERT_EQUAL_STRING("-3:32", deck_core::face(v).remaining);
    v.elapsed = 0;
    v.remaining = 5;
    TEST_ASSERT_EQUAL_STRING("0:00", deck_core::face(v).elapsed);
    TEST_ASSERT_EQUAL_STRING("-0:05", deck_core::face(v).remaining);
}

void test_past_an_hour_times_show_hours() {
    DeckView v = loaded_deck();
    v.elapsed = 3723;
    v.remaining = 3600;
    TEST_ASSERT_EQUAL_STRING("1:02:03", deck_core::face(v).elapsed);
    TEST_ASSERT_EQUAL_STRING("-1:00:00", deck_core::face(v).remaining);
}

void test_with_no_known_length_remaining_is_blank() {
    DeckView v = loaded_deck();
    v.remaining = 0;
    TEST_ASSERT_EQUAL_STRING("", deck_core::face(v).remaining);
    TEST_ASSERT_EQUAL_STRING("1:35", deck_core::face(v).elapsed);
}

void test_the_progress_bar_is_clamped_to_0_1() {
    DeckView v = loaded_deck();
    TEST_ASSERT_EQUAL_FLOAT(0.3125f, deck_core::face(v).progress);
    v.progress = 1.5f;
    TEST_ASSERT_EQUAL_FLOAT(1.0f, deck_core::face(v).progress);
    v.progress = -0.2f;
    TEST_ASSERT_EQUAL_FLOAT(0.0f, deck_core::face(v).progress);
}

// The warning: the last 30 seconds, as DJ players flash it. Not with no known length (remaining 0).
void test_the_bar_warns_in_the_last_30_seconds() {
    TEST_ASSERT_EQUAL(30, deck_core::kEndWarningSeconds);
    DeckView v = loaded_deck();
    v.remaining = 31;
    TEST_ASSERT_FALSE(deck_core::face(v).end_warning);
    v.remaining = 30;
    TEST_ASSERT_TRUE(deck_core::face(v).end_warning);
    v.remaining = 1;
    TEST_ASSERT_TRUE(deck_core::face(v).end_warning);
    v.remaining = 0;
    TEST_ASSERT_FALSE(deck_core::face(v).end_warning);
}

void test_the_beat_lights_its_block_and_none_outside_1_to_4() {
    DeckView v = loaded_deck();
    TEST_ASSERT_EQUAL(3, deck_core::face(v).beat);
    v.beat = 0;
    TEST_ASSERT_EQUAL(0, deck_core::face(v).beat);
    v.beat = 5;
    TEST_ASSERT_EQUAL(0, deck_core::face(v).beat);
}

void test_the_lamps_follow_play_cue_sync_master_and_loop() {
    DeckView v = loaded_deck();
    Face f = deck_core::face(v);
    TEST_ASSERT_TRUE(f.playing && f.sync && f.master && f.loop);
    TEST_ASSERT_FALSE(f.cue);
    v.playing = v.sync = v.master = v.loop = false;
    v.cue = true;
    f = deck_core::face(v);
    TEST_ASSERT_FALSE(f.playing || f.sync || f.master || f.loop);
    TEST_ASSERT_TRUE(f.cue);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_an_empty_deck_shows_no_track_loaded_and_nothing_else);
    RUN_TEST(test_a_loaded_deck_shows_its_title_and_artist);
    RUN_TEST(test_bpm_and_tempo_show_at_2_decimals_tempo_signed);
    RUN_TEST(test_an_unknown_bpm_shows_neither_bpm_nor_tempo);
    RUN_TEST(test_times_show_as_minutes_and_seconds_remaining_with_a_minus);
    RUN_TEST(test_past_an_hour_times_show_hours);
    RUN_TEST(test_with_no_known_length_remaining_is_blank);
    RUN_TEST(test_the_progress_bar_is_clamped_to_0_1);
    RUN_TEST(test_the_bar_warns_in_the_last_30_seconds);
    RUN_TEST(test_the_beat_lights_its_block_and_none_outside_1_to_4);
    RUN_TEST(test_the_lamps_follow_play_cue_sync_master_and_loop);
    return UNITY_END();
}
