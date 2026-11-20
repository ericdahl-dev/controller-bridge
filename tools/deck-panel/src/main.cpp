// The deck panel's test screen (#615): color bars across the whole 800 x 480, a line saying what's running, and the
// last touch. It proves the screen, the color order, the backlight and touch before any of the display feed.
#include <Arduino.h>
#include <Wire.h>
#include <lvgl.h>

#include "board_pins.h"
#include "display_driver.h"
#include "panel_mcu.h"
#include "test_pattern.h"
#include "touch.h"

#ifndef DECK_PANEL_SHA
#define DECK_PANEL_SHA "unknown"
#endif

namespace {

lv_obj_t* g_touch_label = nullptr;
bool g_was_pressed = false;

lv_obj_t* plain_box(lv_obj_t* parent) {
    lv_obj_t* box = lv_obj_create(parent);
    lv_obj_remove_style_all(box);  // no border, radius, padding or shadow: the box is exactly its area
    lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0);
    lv_obj_remove_flag(box, LV_OBJ_FLAG_SCROLLABLE);
    return box;
}

void build_screen() {
    lv_obj_t* screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    for (const test_pattern::Bar& bar : test_pattern::bars(board::LCD_WIDTH)) {
        lv_obj_t* box = plain_box(screen);
        lv_obj_set_pos(box, bar.x, 0);
        lv_obj_set_size(box, bar.width, board::LCD_HEIGHT);
        lv_obj_set_style_bg_color(box, lv_color_make(bar.r, bar.g, bar.b), 0);
    }

    // A black band across the middle carries the text, readable over every bar.
    lv_obj_t* band = plain_box(screen);
    lv_obj_set_size(band, board::LCD_WIDTH, 120);
    lv_obj_align(band, LV_ALIGN_CENTER, 0, 0);
    lv_obj_set_style_bg_color(band, lv_color_black(), 0);

    char line[128];
    snprintf(line, sizeof line, "DeckBridge deck panel  %dx%d  V%d.%d  build %s", board::LCD_WIDTH,
             board::LCD_HEIGHT, CROWPANEL_ADVANCE_REV / 100, (CROWPANEL_ADVANCE_REV / 10) % 10, DECK_PANEL_SHA);
    lv_obj_t* title = lv_label_create(band);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(title, lv_color_white(), 0);
    lv_label_set_text(title, line);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 18);

    g_touch_label = lv_label_create(band);
    lv_obj_set_style_text_font(g_touch_label, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(g_touch_label, lv_color_white(), 0);
    lv_label_set_text(g_touch_label, touch_address() ? "Touch the screen" : "No touch controller found");
    lv_obj_align(g_touch_label, LV_ALIGN_BOTTOM_MID, 0, -18);
}

void show_touch() {
    const bool pressed = touch_pressed();
    if (!pressed || g_touch_label == nullptr) {
        g_was_pressed = pressed;
        return;
    }
    if (!g_was_pressed) Serial.printf("touch: %d,%d\n", touch_x(), touch_y());
    g_was_pressed = true;
    lv_label_set_text_fmt(g_touch_label, "Touch at %d, %d", touch_x(), touch_y());
}

}  // namespace

void setup() {
    Serial.begin(115200);
    Serial.printf("deck panel: boot, build %s\n", DECK_PANEL_SHA);
    Wire.begin(board::I2C_SDA, board::I2C_SCL, board::I2C_HZ);
    // The companion chip can come up after the ESP32 (seen at power-on on a V1.4). Elecrow's V1.3+ example retries,
    // sending the touch-activate byte, until it answers.
    for (int i = 0; i < 20 && !panel_mcu::begin(); ++i) {
        panel_mcu::activateTouch();
        delay(100);
    }
    if (!display_init()) {
        Serial.println("deck panel: no display, restarting in 5 s");
        delay(5000);
        esp_restart();
    }
    touch_init();
    build_screen();
    lv_timer_handler();
    panel_mcu::backlightOn();  // last, after the first draw, so the screen doesn't flash on boot
    Serial.println("deck panel: test screen up");
}

void loop() {
    touch_poll();
    show_touch();
    lv_timer_handler();
    delay(5);
}
