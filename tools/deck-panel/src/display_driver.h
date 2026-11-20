// Panel bring-up for the Elecrow CrowPanel Advance 7.0-HMI. From phrasedeck's display_driver (#615), without its
// rotation and performance counters; see LICENSE.crowpanel-drivers.
//
// Wraps the 800x480 16-bit RGB565 IPS panel in a LovyanGFX device and hands LVGL 9 a pair of draw buffers (internal
// RAM, PSRAM if that's short). It does NOT own the backlight: that's an I2C command to the companion chip
// (panel_mcu.h). Every pin, timing and clock value comes from board_pins.h.
//
// Author: Mark Castelluccio <markacastelluccio@gmail.com>
// Written with assistance from Claude Code (Anthropic).

#pragma once

#include <LovyanGFX.hpp>
// LovyanGFX.hpp does not pull in the RGB parallel bus and panel; they are ESP32-S3 specific.
#include <lgfx/v1/platforms/esp32s3/Bus_RGB.hpp>
#include <lgfx/v1/platforms/esp32s3/Panel_RGB.hpp>
#include <lvgl.h>

#include "board_pins.h"

class LGFX : public lgfx::LGFX_Device {
  public:
    LGFX();

  private:
    lgfx::Bus_RGB bus_;
    lgfx::Panel_RGB panel_;
};

// The single panel instance. Defined in display_driver.cpp.
extern LGFX display_lcd;

// Initializes LVGL, brings up the panel, allocates the draw buffers and registers the LVGL display, with a
// millis()-backed tick, so the caller only pumps lv_timer_handler(). Does NOT turn the backlight on.
//
// Returns false if the panel or the PSRAM allocation failed: fatal, there is nothing to draw on. A full frame at
// 800x480x16 bpp is 768 KB and can't come from internal SRAM, so a build without octal PSRAM fails here.
bool display_init();

// The LVGL display registered by display_init(), or nullptr before it runs.
lv_display_t* display_lvgl();
