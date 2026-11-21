// The panel scan module (#666): the panel's timing, swaps, frames and health in one place, run here against a scripted
// panel so the order of interrupts and loop calls is tested.
#include <unity.h>

#include "panel_scan.h"
#include "scripted_panel.h"

void setUp() {}
void tearDown() {}

using panel_scan::Config;
using panel_scan::Scan;

// The owner's panel: 800x480 at 12.3 MHz, porches 8/4/8 both ways, bounce chunks of 8000 px.
static Config owners(uint32_t bounce_px = 8000, uint32_t pclk_hz = 12300000) {
    return Config{{pclk_hz, 800, 480, 8, 4, 8, 8, 4, 8}, bounce_px};
}

void test_start_gives_the_panel_its_timing() {
    ScriptedPanel panel;
    Scan scan(panel);
    TEST_ASSERT_TRUE(scan.start(owners()));
    TEST_ASSERT_TRUE(panel.started);
    TEST_ASSERT_EQUAL(12300000, panel.config.timing.pclk_hz);
    TEST_ASSERT_EQUAL(8000, panel.config.bounce_px);
    // 820 x 500 clocks at 12.3 MHz: 33333 us a scan-out; a chunk of 8000 px is 10 rows, 666 us.
    TEST_ASSERT_EQUAL(33333, scan.frame_us());
    TEST_ASSERT_EQUAL(666, scan.copy_budget_us());
}

// An odd number of chunks a frame flips which buffer the interrupt refills each frame, and it refills the one going
// out (the banding of #635); a size that doesn't divide the frame is no chunk count at all. Refused, panel untouched.
void test_start_refuses_a_bounce_size_that_isnt_an_even_count_of_chunks() {
    for (uint32_t bad : {7000u, 128000u, 384000u / 3}) {
        ScriptedPanel panel;
        Scan scan(panel);
        TEST_ASSERT_FALSE_MESSAGE(scan.start(owners(bad)), "refused");
        TEST_ASSERT_FALSE(panel.started);
    }
}

// Without bounce buffers there's no copy and no budget.
void test_no_bounce_buffers_has_no_copy_budget() {
    ScriptedPanel panel;
    Scan scan(panel);
    TEST_ASSERT_TRUE(scan.start(owners(0)));
    TEST_ASSERT_EQUAL(0, scan.copy_budget_us());
}

// Another pixel clock is one config change: 16 MHz gives 25625 us and a 512 us chunk.
void test_another_pixel_clock_is_one_change() {
    ScriptedPanel panel;
    Scan scan(panel);
    TEST_ASSERT_TRUE(scan.start(owners(8000, 16000000)));
    TEST_ASSERT_EQUAL(25625, scan.frame_us());
    TEST_ASSERT_EQUAL(512, scan.copy_budget_us());
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_start_gives_the_panel_its_timing);
    RUN_TEST(test_start_refuses_a_bounce_size_that_isnt_an_even_count_of_chunks);
    RUN_TEST(test_no_bounce_buffers_has_no_copy_budget);
    RUN_TEST(test_another_pixel_clock_is_one_change);
    return UNITY_END();
}
