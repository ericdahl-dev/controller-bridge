// The perf build's serial line (#635), once every 5 s: numbers to read next to the owner's eyes.
#include <unity.h>

#include <string>

#include "perf_line.h"

void setUp() {}
void tearDown() {}

static perf_line::Window window() {
    perf_line::Window w;
    w.ms = 5000;
    w.frames.frames = 150;
    w.frames.framesPerSecond = 30.0f;
    w.frames.frameAvgMs = 4.25f;
    w.frames.frameMaxMs = 9.5f;
    w.vsyncs = 195;
    w.swaps = 150;
    w.swap_timeouts = 0;
    w.swap_wait_us = 2700000;  // 18 ms a frame
    w.draw_bitmap_us = 3000;   // 0.02 ms a frame
    w.datagrams = 900;
    w.too_big = 1;
    w.internal_free = 123456;
    return w;
}

void test_the_line_has_every_number_in_one_fixed_order() {
    TEST_ASSERT_EQUAL_STRING(
        "perf: 30.0 frames/s, render avg 4.2 ms max 9.5 ms, swap wait 18.0 ms/frame, draw_bitmap 0.02 ms/frame, "
        "39.0 vsyncs/s, 0 swap timeouts, feed 900 datagrams 1 too big, internal free 123456",
        perf_line::format(window()).c_str());
}

void test_a_window_with_no_frames_says_so_without_dividing_by_zero() {
    perf_line::Window w = window();
    w.frames = {};
    w.swaps = 0;
    w.swap_wait_us = 0;
    w.draw_bitmap_us = 0;
    TEST_ASSERT_EQUAL_STRING(
        "perf: no frames (nothing changed), 39.0 vsyncs/s, 0 swap timeouts, feed 900 datagrams 1 too big, "
        "internal free 123456",
        perf_line::format(w).c_str());
}

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_the_line_has_every_number_in_one_fixed_order);
    RUN_TEST(test_a_window_with_no_frames_says_so_without_dividing_by_zero);
    return UNITY_END();
}
