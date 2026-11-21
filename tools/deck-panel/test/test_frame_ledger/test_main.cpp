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

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_a_read_swapped_and_shown_at_the_next_vsync_is_one_frame_with_its_lag);
    RUN_TEST(test_a_read_after_the_swap_is_not_in_that_frame_but_the_next);
    RUN_TEST(test_a_vsync_that_passes_before_the_read_is_handed_over_marks_its_frame_skipped);
    return UNITY_END();
}
