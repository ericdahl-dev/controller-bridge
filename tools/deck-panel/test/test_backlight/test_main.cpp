// The companion chip's backlight and touch bytes (#615), by board revision. Getting them wrong leaves a black screen
// with no error, so they're pinned here. Values from Elecrow's driver, as phrasedeck's panel_mcu has them.
#include <unity.h>

#include <initializer_list>

#include "backlight.h"

void setUp() {}
void tearDown() {}

static void assert_bytes(const backlight::Bytes& got, std::initializer_list<uint8_t> want) {
    TEST_ASSERT_EQUAL(want.size(), got.count);
    size_t i = 0;
    for (uint8_t b : want) TEST_ASSERT_EQUAL_HEX8(b, got.bytes[i++]);
}

// V1.3 and later (the owner's V1.4 is 140): 0 is brightest, 244 dimmest, 245 off.
void test_v1_4_full_is_0_off_is_245_and_the_scale_runs_backwards() {
    assert_bytes(backlight::level(140, 100), {0});
    assert_bytes(backlight::level(140, 0), {245});
    assert_bytes(backlight::level(140, 50), {122});
    assert_bytes(backlight::level(140, 1), {242});
}

void test_over_100_percent_is_full() { assert_bytes(backlight::level(140, 200), {0}); }

void test_v1_4_touch_activation_is_250() { TEST_ASSERT_EQUAL_HEX8(250, backlight::touch_activate(140)); }

// V1.2: 0x10 on, 0x05 off, and dimming needs 0x10 sent first.
void test_v1_2_sends_on_then_its_level_and_0x05_for_off() {
    assert_bytes(backlight::level(120, 100), {0x10, 0x10});
    assert_bytes(backlight::level(120, 0), {0x05});
    TEST_ASSERT_EQUAL_HEX8(0x19, backlight::touch_activate(120));
}

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_v1_4_full_is_0_off_is_245_and_the_scale_runs_backwards);
    RUN_TEST(test_over_100_percent_is_full);
    RUN_TEST(test_v1_4_touch_activation_is_250);
    RUN_TEST(test_v1_2_sends_on_then_its_level_and_0x05_for_off);
    return UNITY_END();
}
