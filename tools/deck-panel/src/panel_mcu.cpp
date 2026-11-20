// Implementation of the companion MCU driver. From phrasedeck's panel_mcu.cpp (#615); see LICENSE.crowpanel-drivers.
// The revision's bytes are lib/backlight's; this file only puts them on the bus.
//
// Author: Mark Castelluccio <markacastelluccio@gmail.com>
// Written with assistance from Claude Code (Anthropic).

#include "panel_mcu.h"

#include <Arduino.h>
#include <Wire.h>

#include "backlight.h"
#include "board_pins.h"

namespace panel_mcu {
namespace {

int g_revision = 0;

// A single bare byte, no register address. Returns true if the device ACKed.
bool send(uint8_t command) {
    Wire.beginTransmission(board::PANEL_MCU_ADDR);
    Wire.write(command);
    return Wire.endTransmission() == 0;
}

bool present() {
    Wire.beginTransmission(board::PANEL_MCU_ADDR);
    return Wire.endTransmission() == 0;
}

}  // namespace

bool begin() {
    g_revision = 0;

    if (!present()) {
        Serial.printf("panel_mcu: nothing at 0x%02X.\n", board::PANEL_MCU_ADDR);
        Serial.println("panel_mcu: a V1.0 board has an expander at 0x18 instead,");
        Serial.println("panel_mcu: which this firmware does not support.");
        return false;
    }

    // The device ACKs any byte, so probing cannot tell the revisions apart. Trust the compile-time setting.
    g_revision = CROWPANEL_ADVANCE_REV;
    Serial.printf("panel_mcu: found at 0x%02X, driving it as V%d.%d\n",
                  board::PANEL_MCU_ADDR, g_revision / 100, (g_revision / 10) % 10);
    Serial.println("panel_mcu: if the screen stays dark, check the silkscreen and");
    Serial.println("panel_mcu: set CROWPANEL_ADVANCE_REV in platformio.ini.");
    return true;
}

int detectedRevision() { return g_revision; }

void backlightOn() { backlightLevel(100); }

void backlightOff() { backlightLevel(0); }

void backlightLevel(uint8_t percent) {
    const backlight::Bytes out = backlight::level(CROWPANEL_ADVANCE_REV, percent);
    for (uint8_t i = 0; i < out.count; ++i) send(out.bytes[i]);
}

void activateTouch() { send(backlight::touch_activate(CROWPANEL_ADVANCE_REV)); }

}  // namespace panel_mcu
