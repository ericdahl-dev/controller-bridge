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

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_an_empty_deck_shows_no_track_loaded_and_nothing_else);
    RUN_TEST(test_a_loaded_deck_shows_its_title_and_artist);
    return UNITY_END();
}
