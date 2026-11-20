// The deck panel's portable core (#619): display feed bytes in, the screen's decisions out. Built and run on the Mac.
#include <unity.h>

#include "deck_core.h"
#include "osc_bytes.h"
#include "screen_stub.h"

using namespace osc_bytes;

void setUp() {}
void tearDown() {}

static void feed(deck_core::DeckCore& core, const Bytes& b, uint32_t now) { core.feed(b.data(), b.size(), now); }

void test_nothing_heard_yet_is_the_waiting_screen() {
    deck_core::DeckCore core;
    ScreenStub screen;
    core.render(screen, 0);
    TEST_ASSERT_EQUAL(1, screen.shown.size());
    TEST_ASSERT_TRUE(screen.last().waiting);
}

void test_a_deck_message_shows_that_deck() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, int_message(prefix + "deck", 1), 100);
    core.render(screen, 100);
    TEST_ASSERT_FALSE(screen.last().waiting);
    TEST_ASSERT_EQUAL(1, screen.last().deck);
}

void test_color_title_and_artist_show_with_the_deck() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, int_message(prefix + "deck", 3), 100);
    feed(core, int_message(prefix + "color", 0x123456), 101);
    feed(core, string_message(prefix + "title", "Night Drive"), 102);
    feed(core, string_message(prefix + "artist", "Example Artist"), 103);
    core.render(screen, 103);
    TEST_ASSERT_EQUAL(3, screen.last().deck);
    TEST_ASSERT_EQUAL_HEX32(0x123456, screen.last().color);
    TEST_ASSERT_EQUAL_STRING("Night Drive", screen.last().title.c_str());
    TEST_ASSERT_EQUAL_STRING("Example Artist", screen.last().artist.c_str());
}

void test_an_empty_title_clears_the_last_one() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, string_message(prefix + "title", "Night Drive"), 100);
    feed(core, string_message(prefix + "title", ""), 101);
    core.render(screen, 101);
    TEST_ASSERT_EQUAL_STRING("", screen.last().title.c_str());
}

// A bad packet changes nothing: a core that heard only it still shows the waiting screen.
static void assert_ignored(const Bytes& packet) {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, packet, 100);
    core.render(screen, 100);
    TEST_ASSERT_TRUE(screen.last().waiting);
}

void test_an_empty_packet_is_ignored() { assert_ignored({}); }

void test_a_cut_off_packet_is_ignored() {
    Bytes whole = string_message(prefix + "title", "Night Drive");
    for (size_t n = 1; n < whole.size(); ++n) assert_ignored(Bytes(whole.begin(), whole.begin() + n));
}

void test_a_packet_without_a_type_tag_is_ignored() {
    Bytes b;
    put_string(b, prefix + "deck");
    put_int(b, 1);
    assert_ignored(b);
    Bytes no_comma;
    put_string(no_comma, prefix + "deck");
    put_string(no_comma, "ii");
    put_int(no_comma, 1);
    assert_ignored(no_comma);
}

void test_a_value_of_the_wrong_type_is_ignored() {
    assert_ignored(float_message(prefix + "deck", 1.0f));
    assert_ignored(int_message(prefix + "title", 7));
}

void test_more_than_one_value_is_ignored() {
    Bytes b;
    put_string(b, prefix + "deck");
    put_string(b, ",ii");
    put_int(b, 1);
    put_int(b, 2);
    assert_ignored(b);
}

void test_a_length_that_is_not_a_multiple_of_4_is_ignored() {
    Bytes b = int_message(prefix + "deck", 1);
    b.push_back(0);
    assert_ignored(b);
}

void test_an_address_outside_the_prefix_is_ignored() {
    assert_ignored(int_message("/Syndicate/Deck1/deck", 1));
    assert_ignored(int_message("/DeckBridge/Displayx/deck", 1));
}

void test_a_bundle_is_ignored() {
    Bytes b;
    put_string(b, "#bundle");
    put_int(b, 0);
    put_int(b, 1);
    Bytes inner = int_message(prefix + "deck", 1);
    put_int(b, static_cast<int32_t>(inner.size()));
    b.insert(b.end(), inner.begin(), inner.end());
    assert_ignored(b);
}

void test_text_that_is_not_utf8_is_ignored() {
    assert_ignored(string_message(prefix + "title", "Caf\xE9"));  // Latin-1, not UTF-8
    assert_ignored(string_message(prefix + "title", "\xC3"));  // a sequence cut short
    assert_ignored(string_message(prefix + "title", "\xC0\xAF"));  // overlong
}

void test_a_deck_outside_1_to_4_is_ignored() {
    assert_ignored(int_message(prefix + "deck", 0));
    assert_ignored(int_message(prefix + "deck", 5));
}

void test_3_seconds_without_the_feed_is_the_waiting_screen() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, int_message(prefix + "deck", 2), 1000);
    core.render(screen, 3999);
    TEST_ASSERT_FALSE(screen.last().waiting);
    core.render(screen, 4000);
    TEST_ASSERT_TRUE(screen.last().waiting);
}

void test_the_next_message_brings_the_deck_back_as_it_was() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, int_message(prefix + "deck", 2), 1000);
    feed(core, string_message(prefix + "title", "Night Drive"), 1000);
    core.render(screen, 9000);
    TEST_ASSERT_TRUE(screen.last().waiting);
    feed(core, int_message(prefix + "color", 0xFF0000), 9000);
    core.render(screen, 9000);
    TEST_ASSERT_FALSE(screen.last().waiting);
    TEST_ASSERT_EQUAL(2, screen.last().deck);
    TEST_ASSERT_EQUAL_STRING("Night Drive", screen.last().title.c_str());
}

void test_a_message_for_an_address_the_panel_does_not_know_keeps_the_feed_alive() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, int_message(prefix + "deck", 2), 1000);
    feed(core, float_message(prefix + "bpm", 128.0f), 3500);  // a newer DeckBridge's address (ADR 0011)
    core.render(screen, 5000);
    TEST_ASSERT_FALSE(screen.last().waiting);
    TEST_ASSERT_EQUAL(2, screen.last().deck);
}

void test_a_bad_packet_does_not_keep_the_feed_alive() {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, int_message(prefix + "deck", 2), 1000);
    feed(core, int_message("/Syndicate/Deck1/deck", 1), 3500);
    core.render(screen, 4000);
    TEST_ASSERT_TRUE(screen.last().waiting);
}

void test_the_clock_wrapping_round_does_not_end_the_wait_early_or_late() {
    deck_core::DeckCore core;
    ScreenStub screen;
    const uint32_t near_end = 0xFFFFFFFFu - 500;
    feed(core, int_message(prefix + "deck", 1), near_end);
    core.render(screen, near_end + 2999);  // wraps
    TEST_ASSERT_FALSE(screen.last().waiting);
    core.render(screen, near_end + 3000);
    TEST_ASSERT_TRUE(screen.last().waiting);
}

// The board redraws only when something changed, so the core tells the screen only then.
void test_the_screen_hears_only_of_changes() {
    deck_core::DeckCore core;
    ScreenStub screen;
    core.render(screen, 0);
    core.render(screen, 10);
    TEST_ASSERT_EQUAL(1, screen.shown.size());  // waiting, once
    feed(core, int_message(prefix + "deck", 2), 100);
    core.render(screen, 100);
    core.render(screen, 200);
    TEST_ASSERT_EQUAL(2, screen.shown.size());
    feed(core, int_message(prefix + "deck", 2), 300);  // the keepalive snapshot: same value
    core.render(screen, 300);
    TEST_ASSERT_EQUAL(2, screen.shown.size());
    feed(core, string_message(prefix + "title", "Night Drive"), 400);
    core.render(screen, 400);
    TEST_ASSERT_EQUAL(3, screen.shown.size());
    core.render(screen, 400 + 3000);
    core.render(screen, 400 + 4000);
    TEST_ASSERT_EQUAL(4, screen.shown.size());  // waiting, once
    TEST_ASSERT_TRUE(screen.last().waiting);
    feed(core, int_message(prefix + "deck", 2), 5000);
    core.render(screen, 5000);
    TEST_ASSERT_EQUAL(5, screen.shown.size());  // back, unchanged deck shown again
    TEST_ASSERT_FALSE(screen.last().waiting);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_nothing_heard_yet_is_the_waiting_screen);
    RUN_TEST(test_a_deck_message_shows_that_deck);
    RUN_TEST(test_color_title_and_artist_show_with_the_deck);
    RUN_TEST(test_an_empty_title_clears_the_last_one);
    RUN_TEST(test_an_empty_packet_is_ignored);
    RUN_TEST(test_a_cut_off_packet_is_ignored);
    RUN_TEST(test_a_packet_without_a_type_tag_is_ignored);
    RUN_TEST(test_a_value_of_the_wrong_type_is_ignored);
    RUN_TEST(test_more_than_one_value_is_ignored);
    RUN_TEST(test_a_length_that_is_not_a_multiple_of_4_is_ignored);
    RUN_TEST(test_an_address_outside_the_prefix_is_ignored);
    RUN_TEST(test_a_bundle_is_ignored);
    RUN_TEST(test_text_that_is_not_utf8_is_ignored);
    RUN_TEST(test_a_deck_outside_1_to_4_is_ignored);
    RUN_TEST(test_3_seconds_without_the_feed_is_the_waiting_screen);
    RUN_TEST(test_the_next_message_brings_the_deck_back_as_it_was);
    RUN_TEST(test_a_message_for_an_address_the_panel_does_not_know_keeps_the_feed_alive);
    RUN_TEST(test_a_bad_packet_does_not_keep_the_feed_alive);
    RUN_TEST(test_the_clock_wrapping_round_does_not_end_the_wait_early_or_late);
    RUN_TEST(test_the_screen_hears_only_of_changes);
    return UNITY_END();
}
