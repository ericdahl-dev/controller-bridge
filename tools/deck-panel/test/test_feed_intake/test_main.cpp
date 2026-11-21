// The feed's intake (#664): each datagram is stamped when it arrives, off the loop, and queued in fixed memory; the
// frame takes what came since the last one and feeds the core each datagram at its own arrival time.
#include <unity.h>

#include <cstdlib>
#include <vector>

#include "deck_core.h"
#include "feed_intake.h"

void setUp() {}
void tearDown() {}

/// A deck message: /DeckBridge/Display/deck ,i n.
static std::vector<uint8_t> deck_message(uint8_t deck) {
    const char address[] = "/DeckBridge/Display/deck";  // 24 bytes, padded to 28
    std::vector<uint8_t> out(address, address + sizeof address - 1);
    while (out.size() < 28) out.push_back(0);
    const uint8_t tags[] = {',', 'i', 0, 0};
    out.insert(out.end(), tags, tags + 4);
    const uint8_t value[] = {0, 0, 0, deck};
    out.insert(out.end(), value, value + 4);
    return out;
}

struct Last : deck_core::Screen {
    int deck = -1;
    bool waiting = false;
    void show_waiting(const deck_core::WaitingView&, const deck_core::WaitingChanges&) override { waiting = true; }
    void show_deck(const deck_core::Face& f, const deck_core::Changes&) override {
        waiting = false;
        deck = std::atoi(f.deck);
    }
};

static void connect(deck_core::DeckCore& core) { core.set_network(deck_core::Network::connected, "192.168.1.40"); }

// A datagram that arrived at 1.000 s and was read 30 ms later is the core's at 1.000 s: 3 s after its arrival, not
// after the read, the panel goes to waiting.
void test_the_core_gets_each_datagram_at_its_arrival_not_its_read() {
    feed_intake::Intake intake;
    const auto m = deck_message(2);
    TEST_ASSERT_TRUE(intake.push(m.data(), m.size(), 1000000));
    deck_core::DeckCore core;
    connect(core);
    TEST_ASSERT_EQUAL(1, intake.drain(core).count);
    Last screen;
    core.render(screen, 3999);
    TEST_ASSERT_FALSE(screen.waiting);
    TEST_ASSERT_EQUAL(2, screen.deck);
    core.render(screen, 4000);
    TEST_ASSERT_TRUE(screen.waiting);
}

// What came between two frames goes in order, each at its own time; the frame learns the newest arrival, for the
// ledger's lag (#662).
void test_a_frame_takes_everything_since_the_last_in_order_and_knows_the_newest() {
    feed_intake::Intake intake;
    const auto one = deck_message(1), three = deck_message(3);
    intake.push(one.data(), one.size(), 1000000);
    intake.push(three.data(), three.size(), 1010500);
    deck_core::DeckCore core;
    connect(core);
    const feed_intake::Drained got = intake.drain(core);
    TEST_ASSERT_EQUAL(2, got.count);
    TEST_ASSERT_EQUAL_UINT64(1010500, got.newest_us);
    Last screen;
    core.render(screen, 4009);
    TEST_ASSERT_EQUAL(3, screen.deck);
    core.render(screen, 4010);
    TEST_ASSERT_TRUE(screen.waiting);
    // Nothing since: the next frame takes nothing.
    TEST_ASSERT_EQUAL(0, intake.drain(core).count);
}

// Full, the newcomer is dropped and counted; what's queued stays. The feed's 2 s snapshot heals a drop (ADR 0011).
void test_a_full_queue_drops_the_newcomer_and_counts_it() {
    feed_intake::Intake intake;
    const auto two = deck_message(2), four = deck_message(4), one = deck_message(1);
    for (size_t i = 0; i + 1 < feed_intake::kSlots; ++i) TEST_ASSERT_TRUE(intake.push(two.data(), two.size(), 1000));
    TEST_ASSERT_TRUE(intake.push(four.data(), four.size(), 2000));
    TEST_ASSERT_FALSE(intake.push(one.data(), one.size(), 3000));
    TEST_ASSERT_FALSE(intake.push(one.data(), one.size(), 4000));
    TEST_ASSERT_EQUAL_UINT32(2, intake.dropped());
    deck_core::DeckCore core;
    connect(core);
    const feed_intake::Drained got = intake.drain(core);
    TEST_ASSERT_EQUAL(int(feed_intake::kSlots), got.count);
    TEST_ASSERT_EQUAL_UINT64(2000, got.newest_us);
    Last screen;
    core.render(screen, 10);
    TEST_ASSERT_EQUAL(4, screen.deck);
    // Drained, it has room again.
    TEST_ASSERT_TRUE(intake.push(one.data(), one.size(), 5000));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_the_core_gets_each_datagram_at_its_arrival_not_its_read);
    RUN_TEST(test_a_frame_takes_everything_since_the_last_in_order_and_knows_the_newest);
    RUN_TEST(test_a_full_queue_drops_the_newcomer_and_counts_it);
    return UNITY_END();
}
