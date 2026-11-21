// Implementation of the panel driver and the LVGL 9 binding. From phrasedeck (#615), on esp_lcd since #635; see
// LICENSE.crowpanel-drivers.
//
// Author: Mark Castelluccio <markacastelluccio@gmail.com>
// Written with assistance from Claude Code (Anthropic).

#include "display_driver.h"

#include <Arduino.h>
#include <esp_heap_caps.h>
#include <esp_memory_utils.h>
#include <esp_private/periph_ctrl.h>
#include <esp_rom_sys.h>
#include <esp_system.h>
#include <esp_timer.h>
#include <esp_cpu.h>
#include <freertos/FreeRTOS.h>
#include <soc/lcd_cam_struct.h>

#include "board_panel.h"
#include "bounce_budget.h"
#include "frame_pacing.h"
#include "panel_mcu.h"
#include "panel_scan.h"
#ifdef PANEL_PERF_LOG
#include "perf_log.h"
#endif

// The panel's timing, its swaps, the latches the frame clock waits on and their health are lib/panel_scan's Scan
// (#666), host-tested; under it the BoardPanel (board_panel.h) on esp_lcd. This file is LVGL's binding and the perf
// build's copy wrapper, as thin calls into the Scan.

namespace {

constexpr uint32_t SWAP_TIMEOUT_MS = 60;  // nearly two frames at 30 Hz: only a stopped panel misses it

constexpr frame_pacing::Timing TIMING = {
    board::LCD_PCLK_HZ,
    board::LCD_WIDTH,
    board::LCD_HEIGHT,
    board::LCD_HSYNC_FRONT_PORCH,
    board::LCD_HSYNC_PULSE_WIDTH,
    board::LCD_HSYNC_BACK_PORCH,
    board::LCD_VSYNC_FRONT_PORCH,
    board::LCD_VSYNC_PULSE_WIDTH,
    board::LCD_VSYNC_BACK_PORCH,
};

// Static, in internal RAM (.bss), never PSRAM: the panel interrupt reads and writes both, and the frame clock's wake
// path (#663: no PSRAM between the latch and PANEL_DRAW_AT_US) runs through them.
BoardPanel g_board;
panel_scan::Scan g_scan(g_board);
// The perf line's three looks at the health (display_take_perf, _scan, _copy) share one window. Loop only.
panel_scan::HealthLooks g_looks;

#ifdef PANEL_PERF_LOG
// The bounce copy's timing (#635), perf build only: the link wraps memcpy (-Wl,--wrap=memcpy) and the wrapper below
// times the copies of one bounce chunk out of PSRAM, esp_lcd's fill, into the Scan's meter. Every other memcpy pays
// one compare. The copy line's split (#663), by eighth of the scan-out and by loop step, is this file's, under
// g_copy_lock.
portMUX_TYPE g_copy_lock = portMUX_INITIALIZER_UNLOCKED;
const uint32_t g_chunk_ns = bounce_budget::chunk_ns(TIMING, PANEL_BOUNCE_PX);  // once, not per copy
volatile bool g_drawing = false;  // set by the loop around its LVGL refresh, read by the copy
volatile uint8_t g_mark = static_cast<uint8_t>(perf_line::Mark::other);
const uint32_t g_period_us = frame_pacing::frame_us(TIMING);
perf_line::CopySpread g_spread;
// Until when the UART still drains the prints noted (display_note_print), esp_timer us.
volatile uint32_t g_print_until_us = 0;
#endif

lv_display_t* g_disp = nullptr;
// A swap is out: handed over, its release not yet taken. LVGL's task only.
bool g_swap_out = false;
uint32_t g_flush_wait_us = 0;  // LVGL's task only

// Direct mode: px_map is the whole hidden framebuffer and LVGL has drawn the area into it in place, so an area before
// the last needs nothing. The last goes to the panel (BoardPanel::hand_over); flushing stays set until its release
// (flush_wait_cb).
void flush_cb(lv_display_t* disp, const lv_area_t*, uint8_t* px_map) {
    g_board.set_frame(px_map);
    // Read here: LVGL clears the flag at the end of every wait.
    if (g_scan.present(lv_display_flush_is_last(disp))) {
        lv_display_flush_ready(disp);
        return;
    }
    g_swap_out = true;
#ifdef PANEL_PERF_LOG
    // The latches as the hand-over found them, handed to the ledger now the gate is armed.
    const panel_scan::Latches& l = g_board.swap_latches();
    perf_log::frame_swapped(l.count, static_cast<uint32_t>(l.us), g_board.swapped_us());
#endif
}

// With this set, LVGL calls it instead of spinning on flushing, before every flush and after every frame. Only a swap
// waits; everything else returns at once.
//
// The frame clock (#663): LVGL waits once more right after the swap, in the same refresh (lv_refr.c, before it notes
// the areas to copy over next time; nothing is drawn after it). The Scan defers that one: blocking there would hold
// the loop to the next latch and leave the chores no time. The next wait, before anything is drawn or copied into
// the buffer the panel may still show, comes in the next frame, which starts on a latch after the swap
// (display_wait_latch), so it finds the release already given and takes it at once; it still blocks, up to the
// timeout, if it doesn't, so LVGL never draws into the buffer on glass.
void flush_wait_cb(lv_display_t* disp) {
    const int64_t start = esp_timer_get_time();
    const panel_scan::Wait wait = g_scan.wait_release(SWAP_TIMEOUT_MS);
    if (wait == panel_scan::Wait::deferred) return;  // flushing stays set; LVGL reads it nowhere else
    if (g_swap_out) {
        g_swap_out = false;
        g_flush_wait_us += static_cast<uint32_t>(esp_timer_get_time() - start);
#ifdef PANEL_PERF_LOG
        // The take orders this read after the release's stamp. A timeout has no release: its glass time is unknown.
        if (wait == panel_scan::Wait::released) perf_log::frame_on_glass(g_board.release_us());
#endif
    }
    lv_display_flush_ready(disp);
}

uint32_t tick_cb() { return millis(); }

// Runs inside every esp_restart(). The RGB panel's frame loop and its GDMA keep running through a software reset,
// and the next boot then hung often enough for the RTC watchdog to reset it again (phrasedeck #150). Stop both first.
// The backlight goes off first, so the stopped panel isn't seen. Only esp_restart() runs this: a panic, watchdog or
// brownout reset doesn't.
void stopLcdOnRestart() {
    panel_mcu::backlightOff();
    LCD_CAM.lcd_user.lcd_start = 0;
    esp_rom_delay_us(50000);  // the frame in progress ends (one frame is about 26 ms)
    periph_module_reset(PERIPH_LCD_CAM_MODULE);
    periph_module_reset(PERIPH_GDMA_MODULE);
}

const char* region(const void* p) { return esp_ptr_external_ram(p) ? "PSRAM" : "internal RAM"; }

}  // namespace

bool display_init() {
    // The Scan checks the bounce size, then the BoardPanel makes its semaphores and brings the panel up on
    // PANEL_ISR_CORE; its interrupts start inside, routed to the Scan.
    g_board.route(&g_scan);
    if (!g_scan.start(panel_scan::Config{TIMING, PANEL_BOUNCE_PX})) {
        Serial.println("display: the panel didn't start");
        return false;
    }

    void* fb0 = nullptr;
    void* fb1 = nullptr;
    if (!g_board.frame_buffers(&fb0, &fb1)) {
        Serial.println("display: no framebuffers");
        return false;
    }

    lv_init();
    lv_tick_set_cb(tick_cb);

    g_disp = lv_display_create(board::LCD_WIDTH, board::LCD_HEIGHT);
    if (g_disp == nullptr) {
        Serial.println("display: lv_display_create failed");
        return false;
    }
    lv_display_set_flush_cb(g_disp, flush_cb);
    lv_display_set_flush_wait_cb(g_disp, flush_wait_cb);
    // fb1 first: the panel scans fb0 from the start, so LVGL's first frame goes into the hidden one.
    const uint32_t fb_bytes = static_cast<uint32_t>(board::LCD_WIDTH) * board::LCD_HEIGHT * sizeof(uint16_t);
    lv_display_set_buffers(g_disp, fb1, fb0, fb_bytes, LV_DISPLAY_RENDER_MODE_DIRECT);

    // The frame clock refreshes (#663), never LVGL's timer: deleted, so neither lv_timer_handler() nor an invalidation
    // (which resumes a paused one) can start a refresh off the latch.
    lv_display_delete_refr_timer(g_disp);

    Serial.printf("display: %dx%d up, pclk %u Hz, %u fps, frame %u us, refresh on the frame clock, framebuffers %p %p "
                  "in %s\n",
                  board::LCD_WIDTH, board::LCD_HEIGHT, static_cast<unsigned>(board::LCD_PCLK_HZ),
                  static_cast<unsigned>(frame_pacing::frames_per_second(TIMING)),
                  static_cast<unsigned>(g_scan.frame_us()), fb0, fb1, region(fb0));
    Serial.printf("display: bounce buffers %d px, panel interrupts on core %d, loop on core %d, clock edge %s\n",
                  PANEL_BOUNCE_PX, PANEL_ISR_CORE, xPortGetCoreID(), PANEL_PCLK_ACTIVE_NEG ? "falling" : "rising");
    if (esp_register_shutdown_handler(stopLcdOnRestart) != ESP_OK) {
        Serial.println("display: couldn't register the restart handler");
    }
    return true;
}

lv_display_t* display_lvgl() { return g_disp; }

scan_watch::Report display_take_scan() { return g_looks.look(g_scan, panel_scan::HealthLooks::Part::scan).scan; }

DisplayLatch display_latch() {
    const panel_scan::Latches l = g_scan.latches();
    return {l.count, static_cast<uint32_t>(l.us)};
}

// #663's wait on the Scan (#666): the next latch, then the vsync after it, one deadline across both. Without bounce
// buffers the latch is the vsync, so the second returns at once. The newest latch comes back, read after the vsync.
bool display_wait_latch(uint32_t timeout_ms, DisplayLatch& latch) {
    const int64_t until = esp_timer_get_time() + static_cast<int64_t>(timeout_ms) * 1000;
    panel_scan::Latches l;
    if (!g_scan.wait_next_frame(timeout_ms, l)) return false;
    const int64_t left_us = until - esp_timer_get_time();
    const uint32_t left_ms = left_us <= 0 ? 0 : static_cast<uint32_t>((left_us + 999) / 1000);
    if (!g_scan.wait_vsync_after(l, left_ms)) return false;
    latch = display_latch();
    return true;
}

void display_refresh() {
    // lv_refr_now() refreshes only through the display's refresh timer, deleted in display_init(); this is the same
    // refresh, on the default display (the only one).
#ifdef PANEL_PERF_LOG
    g_drawing = true;
#endif
    _lv_display_refr_timer(nullptr);
#ifdef PANEL_PERF_LOG
    g_drawing = false;
#endif
}

uint32_t display_frame_us() { return frame_pacing::frame_us(TIMING); }

uint32_t display_copy_budget_us() { return g_scan.copy_budget_us(); }

// The Scan's meter; it only sees copies in the perf build (the memcpy wrapper below), so empty otherwise.
bounce_budget::Report display_take_copy(DisplayCopyLate* where) {
    const panel_scan::Health& h = g_looks.look(g_scan, panel_scan::HealthLooks::Part::copy);
    if (where != nullptr) *where = {h.copy_late_drawing, h.copy_late_turn};
    return h.copy;
}

#ifdef PANEL_PERF_LOG
void display_mark(perf_line::Mark step) { g_mark = static_cast<uint8_t>(step); }

void display_note_print(uint32_t bytes) {
    // 115200 baud, 10 bits a byte: 87 us each, after whatever is still draining.
    const uint32_t now = static_cast<uint32_t>(esp_timer_get_time());
    const uint32_t from = static_cast<int32_t>(g_print_until_us - now) > 0 ? g_print_until_us : now;
    g_print_until_us = from + bytes * 87u;
}

perf_line::CopySpread display_take_copy_spread() {
    portENTER_CRITICAL(&g_copy_lock);
    const perf_line::CopySpread c = g_spread;
    g_spread = {};
    portEXIT_CRITICAL(&g_copy_lock);
    return c;
}
#endif

DisplayPerf display_take_perf() {
    const panel_scan::Health& h = g_looks.look(g_scan, panel_scan::HealthLooks::Part::counts);
    DisplayPerf p;
    p.vsyncs = h.vsyncs;
    p.swaps = h.swaps;
    p.swap_timeouts = h.swap_timeouts;
    p.draw_bitmap_us = g_board.take_draw_bitmap_us();
    p.flush_wait_us = g_flush_wait_us;
    g_flush_wait_us = 0;
    return p;
}

#ifdef PANEL_PERF_LOG
extern "C" void* __real_memcpy(void* to, const void* from, size_t n);

// In IRAM: memcpy runs everywhere, flash writes included, when the cache is off. Only a copy out of PSRAM, which
// can't happen then, reaches the Scan's and perf_line's flash code. Before the Scan starts (no budget yet) nothing
// is timed.
extern "C" IRAM_ATTR void* __wrap_memcpy(void* to, const void* from, size_t n) {
    if (PANEL_BOUNCE_PX == 0 || n != PANEL_BOUNCE_PX * sizeof(uint16_t) || g_scan.copy_budget_us() == 0 ||
        !esp_ptr_external_ram(from) || esp_ptr_external_ram(to)) {
        return __real_memcpy(to, from, n);
    }
    const uint32_t start = esp_cpu_get_cycle_count();
    void* result = __real_memcpy(to, from, n);
    const uint32_t took_us = (esp_cpu_get_cycle_count() - start) / esp_rom_get_cpu_ticks_per_us();
    // Late as the Scan's meter counts it: longer than the chunk's deadline. The latch time is the BoardPanel's
    // mirror, one aligned word written by the panel interrupt on this core, so no lock per chunk. Where the copy fell
    // is taken at its start: its end less its length.
    const bool late = static_cast<uint64_t>(took_us) * 1000u > g_chunk_ns;
    const int64_t end = esp_timer_get_time();
    const uint32_t end_us = static_cast<uint32_t>(end);
    const uint32_t since_latch_us = end_us - took_us - g_board.latch_us();
    const bool in_isr = xPortInIsrContext();
    const int phase = perf_line::phase(since_latch_us, g_period_us);
    const uint8_t mark = g_mark;
    const bool printing = static_cast<int32_t>(g_print_until_us - end_us) > 0;
    // The meter and the late split (drawing, or the frame turn) are the Scan's, under its own lock.
    g_scan.copied(took_us, static_cast<uint64_t>(end), g_drawing);
    portENTER_CRITICAL_SAFE(&g_copy_lock);
    if (!in_isr) {
        ++g_spread.outside_isr;
        if (late) ++g_spread.late_outside_isr;
    } else {
        ++g_spread.copies_by_phase[phase];
        if (mark < perf_line::kMarks) ++g_spread.copies_by_mark[mark];
        if (late) {
            ++g_spread.late_by_phase[phase];
            if (mark < perf_line::kMarks) ++g_spread.late_by_mark[mark];
            if (g_spread.kept < perf_line::CopySpread::kKept) {
                g_spread.lates[g_spread.kept++] = {since_latch_us, took_us, mark};
            }
        }
        if (printing) {
            ++g_spread.while_printing;
            if (late) ++g_spread.late_while_printing;
        }
    }
    portEXIT_CRITICAL_SAFE(&g_copy_lock);
    return result;
}
#endif
