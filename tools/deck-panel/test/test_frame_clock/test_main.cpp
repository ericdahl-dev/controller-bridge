// The one frame clock (#663): the panel's latch drives read, render, refresh, then the chores.
#include <unity.h>

#include <string>
#include <vector>

#include "frame_clock.h"

void setUp() {}
void tearDown() {}

namespace {

// A test board: latches at given times, a clock that each step advances, and a log of what ran.
struct FakeBoard : frame_clock::Board {
    std::vector<std::string> log;
    uint32_t latch_count = 0;
    uint32_t latch_us = 0;

    bool wait_latch(uint32_t& count, uint32_t& us) override {
        log.push_back("wait");
        ++latch_count;
        latch_us += 33400;
        count = latch_count;
        us = latch_us;
        return true;
    }
    void read_feed() override { log.push_back("read"); }
    void render() override { log.push_back("render"); }
    void refresh() override { log.push_back("refresh"); }
    uint32_t chores_until_us = 0;
    void chores(uint32_t until_us) override {
        log.push_back("chores");
        chores_until_us = until_us;
    }
};

}  // namespace

void test_a_frame_waits_for_the_latch_then_reads_renders_refreshes_and_does_the_chores() {
    FakeBoard board;
    frame_clock::Clock clock(33400, 3000);
    clock.step(board);
    const std::vector<std::string> want = {"wait", "read", "render", "refresh", "chores"};
    TEST_ASSERT_EQUAL(want.size(), board.log.size());
    for (size_t i = 0; i < want.size(); ++i) TEST_ASSERT_EQUAL_STRING(want[i].c_str(), board.log[i].c_str());
}

void test_the_chores_must_end_a_guard_before_the_next_latch() {
    FakeBoard board;
    frame_clock::Clock clock(33400, 3000);  // the scan's period, and the room kept for the next frame's start
    clock.step(board);                      // woken by the latch at 33400
    TEST_ASSERT_EQUAL_UINT32(63800, board.chores_until_us);  // 33400 + 33400 - 3000
}

int main() {
    UNITY_BEGIN();
    RUN_TEST(test_a_frame_waits_for_the_latch_then_reads_renders_refreshes_and_does_the_chores);
    RUN_TEST(test_the_chores_must_end_a_guard_before_the_next_latch);
    return UNITY_END();
}
