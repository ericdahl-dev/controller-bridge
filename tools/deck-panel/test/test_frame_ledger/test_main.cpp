// The frame ledger (#662): arrival to glass per frame, and the frames that missed a vsync.
#include <unity.h>

#include "frame_ledger.h"

void setUp() {}
void tearDown() {}

void test_a_read_swapped_and_shown_at_the_next_vsync_is_one_frame_with_its_lag() {
    frame_ledger::Ledger ledger;
    ledger.read(1000);
    ledger.swapped(9000);
    ledger.on_glass(21000);
    const frame_ledger::Report r = ledger.take();
    TEST_ASSERT_EQUAL_UINT32(1, r.frames);
    TEST_ASSERT_EQUAL_UINT32(20000, r.lag_typical_us);
    TEST_ASSERT_EQUAL_UINT32(20000, r.lag_worst_us);
    TEST_ASSERT_EQUAL_UINT32(0, r.skipped);
}

void test_a_read_after_the_swap_is_not_in_that_frame_but_the_next() {
    frame_ledger::Ledger ledger;
    ledger.read(1000);
    ledger.swapped(9000);
    ledger.read(10000);   // too late for the frame already handed over
    ledger.on_glass(21000);
    ledger.swapped(30000);
    ledger.on_glass(46000);
    const frame_ledger::Report r = ledger.take();
    TEST_ASSERT_EQUAL_UINT32(2, r.frames);
    TEST_ASSERT_EQUAL_UINT32(36000, r.lag_worst_us);  // 10000 to 46000
}

void test_a_vsync_that_passes_before_the_read_is_handed_over_marks_its_frame_skipped() {
    frame_ledger::Ledger ledger;
    ledger.read(1000);
    ledger.vsync(5000);   // a boundary went by with the read not yet drawn
    ledger.swapped(30000);
    ledger.vsync(40000);
    ledger.on_glass(40000);
    ledger.read(41000);
    ledger.swapped(50000);
    ledger.vsync(65000);
    ledger.on_glass(65000);  // in time: the vsync came after the swap
    const frame_ledger::Report r = ledger.take();
    TEST_ASSERT_EQUAL_UINT32(2, r.frames);
    TEST_ASSERT_EQUAL_UINT32(1, r.skipped);
}

void test_lag_counts_from_the_newest_arrival_before_the_read() {
    frame_ledger::Ledger ledger;
    ledger.arrived(500);
    ledger.arrived(800);  // the newest
    ledger.read(1000);
    ledger.swapped(9000);
    ledger.on_glass(21000);
    TEST_ASSERT_EQUAL_UINT32(20200, ledger.take().lag_worst_us);
}

void test_a_vsync_between_arrival_and_read_marks_the_frame_skipped() {
    frame_ledger::Ledger ledger;
    ledger.arrived(500);
    ledger.vsync(3000);  // the datagram sat on the socket across a boundary
    ledger.read(4000);
    ledger.swapped(9000);
    ledger.vsync(21000);
    ledger.on_glass(21000);
    TEST_ASSERT_EQUAL_UINT32(1, ledger.take().skipped);
}

static void frame(frame_ledger::Ledger& ledger, uint32_t read_us, uint32_t lag_us) {
    ledger.read(read_us);
    ledger.swapped(read_us + 1);
    ledger.on_glass(read_us + lag_us);
}

void test_the_typical_lag_is_the_median_of_the_window_and_take_starts_a_new_one() {
    frame_ledger::Ledger ledger;
    const uint32_t lags[] = {10000, 30000, 20000, 90000, 40000};
    uint32_t t = 0;
    for (uint32_t lag : lags) {
        frame(ledger, t, lag);
        t += 100000;
    }
    const frame_ledger::Report r = ledger.take();
    TEST_ASSERT_EQUAL_UINT32(5, r.frames);
    TEST_ASSERT_EQUAL_UINT32(30000, r.lag_typical_us);
    TEST_ASSERT_EQUAL_UINT32(90000, r.lag_worst_us);
    const frame_ledger::Report next = ledger.take();
    TEST_ASSERT_EQUAL_UINT32(0, next.frames);
    TEST_ASSERT_EQUAL_UINT32(0, next.lag_typical_us);
    TEST_ASSERT_EQUAL_UINT32(0, next.lag_worst_us);
}

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_a_read_swapped_and_shown_at_the_next_vsync_is_one_frame_with_its_lag);
    RUN_TEST(test_a_read_after_the_swap_is_not_in_that_frame_but_the_next);
    RUN_TEST(test_a_vsync_that_passes_before_the_read_is_handed_over_marks_its_frame_skipped);
    RUN_TEST(test_lag_counts_from_the_newest_arrival_before_the_read);
    RUN_TEST(test_a_vsync_between_arrival_and_read_marks_the_frame_skipped);
    RUN_TEST(test_the_typical_lag_is_the_median_of_the_window_and_take_starts_a_new_one);
    return UNITY_END();
}
