// Until #621 brings fonts with Latin coverage, the panel draws with LVGL's built-in Montserrat, which has only
// printable ASCII. Text is fitted to it first, so nothing draws as an empty box (#620).
#include <unity.h>

#include <string>

#include "font_fallback.h"

void setUp() {}
void tearDown() {}

static std::string fitted(const char* text) {
    char out[64];
    font_fallback::fit(text, out, sizeof out);
    return out;
}

void test_printable_ascii_is_kept() { TEST_ASSERT_EQUAL_STRING("Night Drive (Extended) #2", fitted("Night Drive (Extended) #2").c_str()); }

void test_accented_latin_letters_lose_their_accents() {
    TEST_ASSERT_EQUAL_STRING("Cafe Angstrom", fitted("Caf\xC3\xA9 \xC3\x85ngstr\xC3\xB6m").c_str());
    TEST_ASSERT_EQUAL_STRING("Senor Unicode", fitted("Se\xC3\xB1or \xC3\x9Cn\xC3\xAF" "code").c_str());
}

void test_the_ellipsis_is_three_dots() { TEST_ASSERT_EQUAL_STRING("Joining Wi-Fi...", fitted("Joining Wi-Fi\xE2\x80\xA6").c_str()); }

void test_anything_else_is_a_question_mark_one_per_character() {
    TEST_ASSERT_EQUAL_STRING("? ? ?", fitted("\xE6\x97\xA5 \xF0\x9F\x8E\xB5 \xC3\x97").c_str());  // 日, 🎵, ×
}

void test_the_output_is_cut_to_its_room_between_characters() {
    char out[5];
    font_fallback::fit("abcdef", out, sizeof out);
    TEST_ASSERT_EQUAL_STRING("abcd", out);
    font_fallback::fit("ab\xE2\x80\xA6", out, sizeof out);  // the dots don't fit whole: none of them
    TEST_ASSERT_EQUAL_STRING("ab", out);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_printable_ascii_is_kept);
    RUN_TEST(test_accented_latin_letters_lose_their_accents);
    RUN_TEST(test_the_ellipsis_is_three_dots);
    RUN_TEST(test_anything_else_is_a_question_mark_one_per_character);
    RUN_TEST(test_the_output_is_cut_to_its_room_between_characters);
    return UNITY_END();
}
