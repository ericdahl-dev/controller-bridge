// Panel bring-up for the Elecrow CrowPanel Advance 7.0-HMI. From phrasedeck's display_driver (#615), moved onto
// ESP-IDF's esp_lcd RGB driver for #635; see LICENSE.crowpanel-drivers.
//
// Drives the 800x480 16-bit RGB565 IPS panel with two full framebuffers in PSRAM. LVGL draws straight into the hidden
// one (direct mode), and the panel switches to it at the next vsync, so a frame is never shown half drawn. It does
// NOT own the backlight: that's an I2C command to the companion chip (panel_mcu.h). Every pin, timing and clock value
// comes from board_pins.h.
//
// Author: Mark Castelluccio <markacastelluccio@gmail.com>
// Written with assistance from Claude Code (Anthropic).

#pragma once

#include <cstdint>

#include <lvgl.h>

#include "board_pins.h"

// Initializes LVGL, brings up the panel and its two framebuffers and registers the LVGL display, with a
// millis()-backed tick, so the caller only pumps lv_timer_handler(). Does NOT turn the backlight on.
//
// Returns false if the panel or its PSRAM framebuffers failed: fatal, there is nothing to draw on. Two frames at
// 800x480x16 bpp are 1.5 MB and can't come from internal SRAM, so a build without octal PSRAM fails here.
bool display_init();

// The LVGL display registered by display_init(), or nullptr before it runs.
lv_display_t* display_lvgl();

// What the panel did since the last call, for a performance log. Call it from LVGL's task (the loop).
struct DisplayPerf {
    uint32_t vsyncs;          // frames the panel scanned out
    uint32_t swaps;           // frames LVGL finished and handed over
    uint32_t swap_timeouts;   // swaps whose vsync didn't come within 60 ms
    uint32_t draw_bitmap_us;  // time in esp_lcd_panel_draw_bitmap (the cache write-back and the swap)
    uint32_t flush_wait_us;   // time LVGL waited for a swap's vsync
};
DisplayPerf display_take_perf();
