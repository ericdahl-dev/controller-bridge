// The perf build's serial line (#635), once every 5 s: numbers to read next to the owner's eyes.
#include <unity.h>

#include <string>

#include "perf_line.h"

void setUp() {}
void tearDown() {}

static perf_line::Window window() {
    perf_line::Window w;
    w.ms = 5000;
    w.frames = 150;           // in this window: 30 a second
    w.frame_us = 3300000;     // 22 ms each, the swap wait included
    w.frame_max_us = 31500;
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
        "perf: 30.0 frames/s, frame avg 22.0 ms max 31.5 ms (swap wait 18.0), draw_bitmap 0.02 ms/frame, "
        "39.0 vsyncs/s, 0 swap timeouts, feed 900 datagrams 1 too big, internal free 123456",
        perf_line::format(window()).c_str());
}

void test_a_window_with_no_frames_says_so_without_dividing_by_zero() {
    perf_line::Window w = window();
    w.frames = 0;
    w.frame_us = 0;
    w.frame_max_us = 0;
    w.swaps = 0;
    w.swap_wait_us = 0;
    w.draw_bitmap_us = 0;
    TEST_ASSERT_EQUAL_STRING(
        "perf: no frames (nothing changed), 39.0 vsyncs/s, 0 swap timeouts, feed 900 datagrams 1 too big, "
        "internal free 123456",
        perf_line::format(w).c_str());
}

// The frames are counted in the same window as everything else on the line, so a busy screen never reads as still.
void test_frames_per_second_comes_from_this_windows_own_length() {
    perf_line::Window w = window();
    w.ms = 2500;
    w.frames = 75;
    w.frame_us = 75 * 22000;
    w.vsyncs = 98;
    const std::string line = perf_line::format(w);
    TEST_ASSERT_TRUE(line.rfind("perf: 30.0 frames/s, frame avg 22.0 ms", 0) == 0);
    TEST_ASSERT_TRUE(line.find("39.2 vsyncs/s") != std::string::npos);
}

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_the_line_has_every_number_in_one_fixed_order);
    RUN_TEST(test_a_window_with_no_frames_says_so_without_dividing_by_zero);
    RUN_TEST(test_frames_per_second_comes_from_this_windows_own_length);
    return UNITY_END();
}
