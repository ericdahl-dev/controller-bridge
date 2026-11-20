// The panel's receive path (#620): on the loop task, each frame reads waiting datagrams into the core, at most a few,
// so a burst can't hold the screen up. A datagram too big for the buffer is dropped, never cut and parsed.
#include <unity.h>

#include <deque>
#include <vector>

#include "deck_core.h"
#include "feed_drain.h"

void setUp() {}
void tearDown() {}

/// Datagrams waiting on a fake socket.
struct FakeSocket : feed_drain::Socket {
    std::deque<std::vector<uint8_t>> waiting;
    size_t next_size() override { return waiting.empty() ? 0 : waiting.front().size(); }
    size_t read(uint8_t* into, size_t room) override {
        std::vector<uint8_t> d = waiting.front();
        waiting.pop_front();
        size_t n = d.size() < room ? d.size() : room;
        for (size_t i = 0; i < n; ++i) into[i] = d[i];
        return n;
    }
    void skip() override { waiting.pop_front(); }
};

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
    void show_waiting(const deck_core::WaitingView&) override { waiting = true; }
    void show_deck(const deck_core::DeckView& v) override {
        waiting = false;
        deck = v.deck;
    }
};

void test_waiting_datagrams_go_to_the_core_in_order() {
    FakeSocket socket;
    socket.waiting = {deck_message(1), deck_message(3)};
    deck_core::DeckCore core;
    feed_drain::Drain drain;
    TEST_ASSERT_EQUAL(2, drain.run(socket, core, 100));
    Last screen;
    core.render(screen, 100);
    TEST_ASSERT_EQUAL(3, screen.deck);
}

void test_a_frame_reads_at_most_a_few_the_rest_wait_for_the_next() {
    FakeSocket socket;
    for (int i = 0; i < feed_drain::kPerFrame + 3; ++i) socket.waiting.push_back(deck_message(2));
    deck_core::DeckCore core;
    feed_drain::Drain drain;
    TEST_ASSERT_EQUAL(feed_drain::kPerFrame, drain.run(socket, core, 100));
    TEST_ASSERT_EQUAL(3, socket.waiting.size());
    TEST_ASSERT_EQUAL(3, drain.run(socket, core, 110));
}

void test_a_datagram_too_big_is_dropped_and_counted() {
    FakeSocket socket;
    std::vector<uint8_t> big = deck_message(4);
    big.resize(feed_drain::kMaxDatagram + 4, 0);
    socket.waiting = {big, deck_message(1)};
    deck_core::DeckCore core;
    feed_drain::Drain drain;
    drain.run(socket, core, 100);
    TEST_ASSERT_EQUAL(1, drain.too_big());
    TEST_ASSERT_TRUE(socket.waiting.empty());
    Last screen;
    core.render(screen, 100);
    TEST_ASSERT_EQUAL(1, screen.deck);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_waiting_datagrams_go_to_the_core_in_order);
    RUN_TEST(test_a_frame_reads_at_most_a_few_the_rest_wait_for_the_next);
    RUN_TEST(test_a_datagram_too_big_is_dropped_and_counted);
    return UNITY_END();
}
