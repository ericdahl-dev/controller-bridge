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
    TEST_ASSERT_EQUAL(1, intake.drain(core));
    Last screen;
    core.render(screen, 3999);
    TEST_ASSERT_FALSE(screen.waiting);
    TEST_ASSERT_EQUAL(2, screen.deck);
    core.render(screen, 4000);
    TEST_ASSERT_TRUE(screen.waiting);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_the_core_gets_each_datagram_at_its_arrival_not_its_read);
    return UNITY_END();
}
