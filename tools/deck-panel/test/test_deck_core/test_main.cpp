// The deck panel's portable core (#619): display feed bytes in, the screen's decisions out. Built and run on the Mac.
#include <unity.h>

#include <fstream>
#include <sstream>

#include "deck_core.h"
#include "json_mini.h"
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

static std::string repeat(const std::string& piece, size_t times) {
    std::string out;
    for (size_t i = 0; i < times; ++i) out += piece;
    return out;
}

static std::string title_shown(const std::string& title) {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, string_message(prefix + "title", title), 100);
    core.render(screen, 100);
    return screen.last().title;
}

static std::string artist_shown(const std::string& artist) {
    deck_core::DeckCore core;
    ScreenStub screen;
    feed(core, string_message(prefix + "artist", artist), 100);
    core.render(screen, 100);
    return screen.last().artist;
}

static const std::string ellipsis = "\xE2\x80\xA6";  // …

void test_a_title_that_fits_is_shown_whole() {
    std::string fits = repeat("a", deck_core::kTitleMax);
    TEST_ASSERT_EQUAL_STRING(fits.c_str(), title_shown(fits).c_str());
}

void test_a_long_title_is_cut_with_an_ellipsis_to_the_limit() {
    std::string want = repeat("a", deck_core::kTitleMax - 1) + ellipsis;
    TEST_ASSERT_EQUAL_STRING(want.c_str(), title_shown(repeat("a", deck_core::kTitleMax + 1)).c_str());
}

void test_a_long_artist_is_cut_too() {
    std::string want = repeat("b", deck_core::kArtistMax - 1) + ellipsis;
    TEST_ASSERT_EQUAL_STRING(want.c_str(), artist_shown(repeat("b", deck_core::kArtistMax + 5)).c_str());
}

void test_the_cut_counts_characters_not_bytes_and_never_splits_one() {
    // é is 2 bytes, the emoji 4: the limit is in characters, and the cut lands between them.
    std::string fits = repeat("\xC3\xA9", deck_core::kTitleMax);
    TEST_ASSERT_EQUAL_STRING(fits.c_str(), title_shown(fits).c_str());
    std::string want = repeat("\xF0\x9F\x8E\xB5", deck_core::kTitleMax - 1) + ellipsis;
    TEST_ASSERT_EQUAL_STRING(want.c_str(), title_shown(repeat("\xF0\x9F\x8E\xB5", deck_core::kTitleMax + 1)).c_str());
}

void test_spaces_before_the_ellipsis_are_dropped() {
    std::string words = repeat("a", deck_core::kTitleMax - 3) + "   " + "tail";
    std::string want = repeat("a", deck_core::kTitleMax - 3) + ellipsis;
    TEST_ASSERT_EQUAL_STRING(want.c_str(), title_shown(words).c_str());
}

// The shared examples (#490 seam 3): feed/examples.json says, for each deck state, the messages DeckBridge sends. Its
// Swift test (DisplayFeedExamplesTests) checks DeckBridge sends them; this checks the panel shows that state from them.
static json_mini::Value examples() {
    std::string here = __FILE__;
    std::string path = here.substr(0, here.rfind('/')) + "/../../feed/examples.json";
    std::ifstream file(path);
    TEST_ASSERT_TRUE_MESSAGE(file.good(), ("can't open " + path).c_str());
    std::stringstream text;
    text << file.rdbuf();
    return json_mini::parse(text.str());
}

static Bytes example_message(const json_mini::Value& m) {
    const std::string& address = m["address"].string;
    const std::string& type = m["type"].string;
    if (type == "i") return int_message(address, static_cast<int32_t>(m["value"].number));
    if (type == "f") return float_message(address, static_cast<float>(m["value"].number));
    if (type == "s") return string_message(address, m["value"].string);
    TEST_FAIL_MESSAGE(("a type that isn't i, f or s: " + type).c_str());
    return {};
}

void test_the_shared_examples_prefix_is_the_panels() {
    const json_mini::Value file = examples();
    TEST_ASSERT_EQUAL_STRING(prefix.c_str(), file["prefix"].string.c_str());
    TEST_ASSERT_TRUE(file["cases"].array.size() >= 3);
}

void test_each_shared_example_shows_its_deck_state() {
    const json_mini::Value file = examples();  // held here: a range-for over examples()["cases"] would dangle
    size_t walked = 0;
    for (const json_mini::Value& example : file["cases"].array) {
        ++walked;
        const char* name = example["name"].string.c_str();
        deck_core::DeckCore core;
        ScreenStub screen;
        for (const json_mini::Value& m : example["messages"].array) feed(core, example_message(m), 100);
        core.render(screen, 100);
        // A key this walker doesn't know (a later field, #617) is left for its own test.
        const json_mini::Value& state = example["state"];
        const auto& rgb = state["color"].array;
        uint32_t color = static_cast<uint32_t>(rgb[0].number) << 16 | static_cast<uint32_t>(rgb[1].number) << 8 |
                         static_cast<uint32_t>(rgb[2].number);
        TEST_ASSERT_FALSE_MESSAGE(screen.last().waiting, name);
        TEST_ASSERT_EQUAL_MESSAGE(static_cast<int>(state["deck"].number), screen.last().deck, name);
        TEST_ASSERT_EQUAL_HEX32_MESSAGE(color, screen.last().color, name);
        TEST_ASSERT_EQUAL_STRING_MESSAGE(state["title"].string.c_str(), screen.last().title.c_str(), name);
        TEST_ASSERT_EQUAL_STRING_MESSAGE(state["artist"].string.c_str(), screen.last().artist.c_str(), name);
    }
    TEST_ASSERT_EQUAL(file["cases"].array.size(), walked);
    TEST_ASSERT_TRUE(walked >= 3);
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
    RUN_TEST(test_a_title_that_fits_is_shown_whole);
    RUN_TEST(test_a_long_title_is_cut_with_an_ellipsis_to_the_limit);
    RUN_TEST(test_a_long_artist_is_cut_too);
    RUN_TEST(test_the_cut_counts_characters_not_bytes_and_never_splits_one);
    RUN_TEST(test_spaces_before_the_ellipsis_are_dropped);
    RUN_TEST(test_the_shared_examples_prefix_is_the_panels);
    RUN_TEST(test_each_shared_example_shows_its_deck_state);
    return UNITY_END();
}
