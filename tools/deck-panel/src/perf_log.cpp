#include "perf_log.h"

#ifdef PANEL_PERF_LOG

#include <Arduino.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>
#include <lvgl.h>

#include "display_driver.h"
#include "perf_line.h"

namespace perf_log {
namespace {

constexpr uint32_t kWindowMs = 5000;

// This window's frames: refreshes that flushed something, timed start to end.
uint32_t g_frames = 0;
uint64_t g_frame_us = 0;
uint32_t g_frame_max_us = 0;
uint32_t g_refresh_start_us = 0;
uint32_t g_refresh_px = 0;

uint32_t g_window_start_ms = 0;
uint32_t g_datagrams = 0;
uint32_t g_too_big_at_start = 0;
uint32_t g_too_big = 0;

void on_event(lv_event_t* e) {
    switch (lv_event_get_code(e)) {
        case LV_EVENT_REFR_START:
            g_refresh_start_us = micros();
            g_refresh_px = 0;
            break;
        case LV_EVENT_FLUSH_START: {
            const lv_area_t* a = static_cast<const lv_area_t*>(lv_event_get_param(e));
            if (a) g_refresh_px += static_cast<uint32_t>(lv_area_get_size(a));
            break;
        }
        case LV_EVENT_REFR_READY: {
            if (g_refresh_px == 0) break;  // nothing drawn: not a frame
            const uint32_t took = micros() - g_refresh_start_us;
            ++g_frames;
            g_frame_us += took;
            if (took > g_frame_max_us) g_frame_max_us = took;
            break;
        }
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
    lv_display_add_event_cb(disp, on_event, LV_EVENT_REFR_READY, nullptr);
    display_take_perf();  // start the driver's counts from here
    g_window_start_ms = millis();
    Serial.println("perf: on, a line every 5 s");
}

void tick(uint32_t now_ms, int datagrams, uint32_t too_big) {
    if (datagrams > 0) g_datagrams += static_cast<uint32_t>(datagrams);
    g_too_big = too_big;
    if (now_ms - g_window_start_ms < kWindowMs) return;

    const DisplayPerf d = display_take_perf();
    perf_line::Window w;
    w.ms = now_ms - g_window_start_ms;
    w.frames = g_frames;
    w.frame_us = g_frame_us;
    w.frame_max_us = g_frame_max_us;
    w.vsyncs = d.vsyncs;
    w.swaps = d.swaps;
    w.swap_timeouts = d.swap_timeouts;
    w.swap_wait_us = d.flush_wait_us;
    w.draw_bitmap_us = d.draw_bitmap_us;
    w.datagrams = g_datagrams;
    w.too_big = g_too_big - g_too_big_at_start;
    w.internal_free = static_cast<uint32_t>(heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
    Serial.println(perf_line::format(w).c_str());

    g_frames = 0;
    g_frame_us = 0;
    g_frame_max_us = 0;
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
