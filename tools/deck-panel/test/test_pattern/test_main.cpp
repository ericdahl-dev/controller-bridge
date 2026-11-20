// The test screen's color bars (#615): what the panel draws first, to prove the whole 800 x 480 is driven.
#include <unity.h>

#include "test_pattern.h"

void setUp() {}
void tearDown() {}

void test_the_bars_cover_the_whole_width_with_no_gap_or_overlap() {
    const auto bars = test_pattern::bars(800);
    int next = 0;
    for (const auto& bar : bars) {
        TEST_ASSERT_EQUAL(next, bar.x);
        TEST_ASSERT_TRUE(bar.width > 0);
        next = bar.x + bar.width;
    }
    TEST_ASSERT_EQUAL(800, next);
}

void test_a_width_that_does_not_divide_evenly_still_ends_at_the_edge() {
    const auto bars = test_pattern::bars(799);
    const auto& last = bars[bars.size() - 1];
    TEST_ASSERT_EQUAL(799, last.x + last.width);
}

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_the_bars_cover_the_whole_width_with_no_gap_or_overlap);
    RUN_TEST(test_a_width_that_does_not_divide_evenly_still_ends_at_the_edge);
    return UNITY_END();
}
