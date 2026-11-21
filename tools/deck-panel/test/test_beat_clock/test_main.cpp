// The panel's beat clock (#660): the master clock's beat at any time, from the beat edges the feed brings.
#include <unity.h>

#include "beat_clock.h"

void setUp() {}
void tearDown() {}

using deck_core::BeatClock;

void test_no_beat_heard_is_none() {
    BeatClock clock;
    TEST_ASSERT_EQUAL(0, clock.beat_at(0));
    TEST_ASSERT_EQUAL(0, clock.beat_at(10000));
}

// One edge gives no tempo: the beat heard holds until the next.
void test_one_edge_holds_its_beat() {
    BeatClock clock;
    clock.edge(3, 100);
    TEST_ASSERT_EQUAL(3, clock.beat_at(100));
    TEST_ASSERT_EQUAL(3, clock.beat_at(5000));
}

// 0 is DeckBridge's "the clock has been quiet over 2 s": no beat.
void test_beat_0_is_none() {
    BeatClock clock;
    clock.edge(3, 100);
    clock.edge(0, 2200);
    TEST_ASSERT_EQUAL(0, clock.beat_at(2200));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_no_beat_heard_is_none);
    RUN_TEST(test_one_edge_holds_its_beat);
    RUN_TEST(test_beat_0_is_none);
    return UNITY_END();
}
