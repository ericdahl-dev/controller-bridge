#include "perf_log.h"

#ifdef PANEL_PERF_LOG

#include <Arduino.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>
#include <lvgl.h>

#include "display_driver.h"
#include "frame_stats.h"
#include "perf_line.h"

namespace perf_log {
namespace {

frame_stats::Stats g_stats;
frame_stats::Report g_report;  // the last full window's frames
bool g_have_report = false;

uint32_t g_window_start_ms = 0;
uint32_t g_datagrams = 0;
uint32_t g_too_big_at_start = 0;
uint32_t g_too_big = 0;
int64_t g_flush_started_us = 0;
uint32_t g_flush_px = 0;

void on_event(lv_event_t* e) {
    switch (lv_event_get_code(e)) {
        case LV_EVENT_REFR_START:
            frame_stats::refreshStart(g_stats, micros());
            break;
        case LV_EVENT_FLUSH_START: {
            const lv_area_t* a = static_cast<const lv_area_t*>(lv_event_get_param(e));
            g_flush_px = a ? static_cast<uint32_t>(lv_area_get_size(a)) : 0;
            g_flush_started_us = esp_timer_get_time();
            break;
        }
        case LV_EVENT_FLUSH_FINISH:
            frame_stats::flushed(g_stats, g_flush_px, static_cast<uint32_t>(esp_timer_get_time() - g_flush_started_us));
            break;
        case LV_EVENT_REFR_READY:
            if (frame_stats::refreshReady(g_stats, micros(), millis(), g_report)) g_have_report = true;
            break;
        default:
            break;
    }
}

}  // namespace

void begin() {
    lv_display_t* disp = display_lvgl();
    if (disp == nullptr) return;
    lv_display_add_event_cb(disp, on_event, LV_EVENT_REFR_START, nullptr);
    lv_display_add_event_cb(disp, on_event, LV_EVENT_FLUSH_START, nullptr);
    lv_display_add_event_cb(disp, on_event, LV_EVENT_FLUSH_FINISH, nullptr);
    lv_display_add_event_cb(disp, on_event, LV_EVENT_REFR_READY, nullptr);
    display_take_perf();  // start the driver's counts from here
    g_window_start_ms = millis();
    Serial.println("perf: on, a line every 5 s");
}

void tick(uint32_t now_ms, int datagrams, uint32_t too_big) {
    if (datagrams > 0) g_datagrams += static_cast<uint32_t>(datagrams);
    g_too_big = too_big;
    if (now_ms - g_window_start_ms < frame_stats::kWindowMs) return;

    const DisplayPerf d = display_take_perf();
    perf_line::Window w;
    w.ms = now_ms - g_window_start_ms;
    // frame_stats closes its own window on a frame; a still screen has none, so it says so.
    if (g_have_report) w.frames = g_report;
    w.vsyncs = d.vsyncs;
    w.swaps = d.swaps;
    w.swap_timeouts = d.swap_timeouts;
    w.swap_wait_us = d.flush_wait_us;
    w.draw_bitmap_us = d.draw_bitmap_us;
    w.datagrams = g_datagrams;
    w.too_big = g_too_big - g_too_big_at_start;
    w.internal_free = static_cast<uint32_t>(heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
    Serial.println(perf_line::format(w).c_str());

    g_have_report = false;
    g_window_start_ms = now_ms;
    g_datagrams = 0;
    g_too_big_at_start = g_too_big;
}

}  // namespace perf_log

#else

namespace perf_log {
void begin() {}
void tick(uint32_t, int, uint32_t) {}
}  // namespace perf_log

#endif
