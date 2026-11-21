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

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_a_read_swapped_and_shown_at_the_next_vsync_is_one_frame_with_its_lag);
    return UNITY_END();
}
