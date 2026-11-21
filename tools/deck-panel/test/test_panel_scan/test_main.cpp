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


using Irq = ScriptedPanel::Irq;

// Areas before a frame's last are drawn in place and released at once; the last hands the buffer to the panel.
void test_only_a_frames_last_area_goes_to_the_panel() {
    ScriptedPanel panel;
    Scan scan(panel);
    panel.scan = &scan;
    scan.start(owners());
    TEST_ASSERT_TRUE(scan.present(false));
    TEST_ASSERT_EQUAL(0, panel.hand_overs);
    TEST_ASSERT_FALSE(scan.present(true));
    TEST_ASSERT_EQUAL(1, panel.hand_overs);
}

// Bounce buffers: the driver takes the next buffer at frame complete, when the last chunk of this one is copied, not at
// the vsync. A swap released at the vsync would let LVGL draw into a buffer still feeding a whole frame (#635).
void test_with_bounce_buffers_the_frame_end_releases_a_swap_not_the_vsync() {
    ScriptedPanel panel;
    Scan scan(panel);
    panel.scan = &scan;
    scan.start(owners());
    panel.script = {{1000, Irq::vsync}, {20000, Irq::frame_complete}};
    scan.present(true);
    TEST_ASSERT_TRUE(scan.wait_release(60));
    TEST_ASSERT_EQUAL(20000, panel.now_us);  // not 1000
}

// Without bounce buffers the GDMA reads the framebuffer itself, from the vsync on: the vsync releases it.
void test_without_bounce_buffers_the_vsync_releases_a_swap() {
    ScriptedPanel panel;
    Scan scan(panel);
    panel.scan = &scan;
    scan.start(owners(0));
    panel.script = {{1000, Irq::vsync}};
    scan.present(true);
    TEST_ASSERT_TRUE(scan.wait_release(60));
    TEST_ASSERT_EQUAL(1000, panel.now_us);
}

// Nothing handed over: nothing to wait for.
void test_with_no_swap_out_the_wait_returns_at_once() {
    ScriptedPanel panel;
    Scan scan(panel);
    panel.scan = &scan;
    scan.start(owners());
    panel.script = {{20000, Irq::frame_complete}};
    TEST_ASSERT_TRUE(scan.wait_release(60));
    TEST_ASSERT_EQUAL(0, panel.now_us);
}


// No latch in time (a stopped panel): the wait gives up and says so.
void test_a_release_that_never_comes_times_out() {
    ScriptedPanel panel;
    Scan scan(panel);
    panel.scan = &scan;
    scan.start(owners());
    scan.present(true);
    TEST_ASSERT_FALSE(scan.wait_release(60));
    TEST_ASSERT_EQUAL(60000, panel.now_us);
}

// The latch for a timed-out swap comes as the wait gives up, after the semaphore timed out but before the gate hears
// of it, so it gives. That give is stale: the next swap still waits for its own latch, or LVGL draws into the buffer
// on glass.
void test_a_late_latch_never_releases_the_next_swap() {
    ScriptedPanel panel;
    Scan scan(panel);
    panel.scan = &scan;
    scan.start(owners());
    panel.script = {{60000, Irq::frame_complete}, {93333, Irq::frame_complete}};
    scan.present(true);
    TEST_ASSERT_FALSE(scan.wait_release(60));  // gives up at 60 ms, as the latch comes
    scan.present(true);
    TEST_ASSERT_TRUE(scan.wait_release(60));
    TEST_ASSERT_EQUAL(93333, panel.now_us);  // its own latch, not the stale one
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_start_gives_the_panel_its_timing);
    RUN_TEST(test_start_refuses_a_bounce_size_that_isnt_an_even_count_of_chunks);
    RUN_TEST(test_no_bounce_buffers_has_no_copy_budget);
    RUN_TEST(test_another_pixel_clock_is_one_change);
    RUN_TEST(test_only_a_frames_last_area_goes_to_the_panel);
    RUN_TEST(test_with_bounce_buffers_the_frame_end_releases_a_swap_not_the_vsync);
    RUN_TEST(test_without_bounce_buffers_the_vsync_releases_a_swap);
    RUN_TEST(test_with_no_swap_out_the_wait_returns_at_once);
    RUN_TEST(test_a_release_that_never_comes_times_out);
    RUN_TEST(test_a_late_latch_never_releases_the_next_swap);
    return UNITY_END();
}
