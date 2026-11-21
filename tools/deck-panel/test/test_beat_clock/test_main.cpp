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


// 128 BPM: a beat every 469 ms (468.75). Two edges give the tempo; the next beat shows when it's due, before its
// message, and no further than kPredictBeats past the last edge heard.
void test_the_next_beat_shows_when_due_before_its_message() {
    BeatClock clock;
    clock.edge(1, 1000);
    clock.edge(2, 1469);
    TEST_ASSERT_EQUAL(2, clock.beat_at(1937));
    TEST_ASSERT_EQUAL(3, clock.beat_at(1938));
    TEST_ASSERT_EQUAL(1, BeatClock::kPredictBeats);
    TEST_ASSERT_EQUAL(3, clock.beat_at(2407));  // the beat after is due too, but never two past the last edge
    TEST_ASSERT_EQUAL(3, clock.beat_at(9000));
}

// After 4 comes 1.
void test_after_4_comes_1() {
    BeatClock clock;
    clock.edge(3, 1000);
    clock.edge(4, 1469);
    TEST_ASSERT_EQUAL(1, clock.beat_at(1938));
}

// The keepalive sends the same beat again: no edge, so no tempo from it.
void test_the_same_beat_again_is_no_edge() {
    BeatClock clock;
    clock.edge(1, 1000);
    clock.edge(1, 1200);
    clock.edge(2, 1469);
    TEST_ASSERT_EQUAL(3, clock.beat_at(1938));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_no_beat_heard_is_none);
    RUN_TEST(test_one_edge_holds_its_beat);
    RUN_TEST(test_beat_0_is_none);
    RUN_TEST(test_the_next_beat_shows_when_due_before_its_message);
    RUN_TEST(test_after_4_comes_1);
    RUN_TEST(test_the_same_beat_again_is_no_edge);
    return UNITY_END();
}
