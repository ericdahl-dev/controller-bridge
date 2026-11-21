// The deck panel (#490, #620): joins Wi-Fi, listens for DeckBridge's display feed and shows the deck in front, or the
// waiting screen with its address and port. Everything runs on Arduino's loop task: the core isn't thread-safe, so
// the UDP socket is polled here, never read from a callback. Built with DECK_PANEL_TEST_SCREEN (env crowpanel-test),
// it shows the test screen (#615) instead, with no Wi-Fi.
#include <Arduino.h>
#include <Wire.h>
#include <esp_heap_caps.h>
#include <lvgl.h>

#include "board_pins.h"
#include "display_driver.h"
#include "panel_mcu.h"
#include "perf_log.h"
#include "touch.h"

#ifdef DECK_PANEL_TEST_SCREEN
#include "test_screen.h"
#else
#include "deck_core.h"
#include "deck_view.h"
#include "feed_drain.h"
#include "feed_udp.h"
#include "hold_reset.h"
#include "wifi_link.h"
#endif

#ifndef DECK_PANEL_SHA
#define DECK_PANEL_SHA "unknown"
#endif

namespace {

#ifndef DECK_PANEL_TEST_SCREEN
// Static, not loop() locals: the drain's 512-byte buffer and the view's text stay off the loop task's 8 KB stack.
deck_core::DeckCore g_core;
feed_drain::Drain g_drain;
FeedUdp g_udp;
DeckScreen g_screen;
wifi_setup::HoldReset g_hold;
uint32_t g_too_big = 0;
uint32_t g_health_ms = 0;

/// Once a minute on serial: the loop task's spare stack and internal RAM, the numbers a long run needs.
void log_health(uint32_t now_ms) {
    constexpr uint32_t kEveryMs = 60000;
    if (now_ms - g_health_ms < kEveryMs) return;
    g_health_ms = now_ms;
    Serial.printf("deck panel: loop stack free %u B, internal heap free %u B (lowest %u B)\n",
                  unsigned(uxTaskGetStackHighWaterMark(nullptr) * sizeof(StackType_t)),
                  unsigned(heap_caps_get_free_size(MALLOC_CAP_INTERNAL)),
                  unsigned(heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL)));
}
#endif

void build_screen() {
#ifdef DECK_PANEL_TEST_SCREEN
    test_screen::build();
#else
    g_screen.build();
    // The first frame says what's true before Wi-Fi starts: the core takes the network as up until told.
    g_core.set_network(wifi_link::state(), wifi_link::ip());
    g_core.set_setup(wifi_link::setup_name(), wifi_link::setup_password());
    g_core.render(g_screen, millis());
#endif
}

}  // namespace

void setup() {
    Serial.begin(115200);
    Serial.printf("deck panel: boot, build %s\n", DECK_PANEL_SHA);
    Wire.begin(board::I2C_SDA, board::I2C_SCL, board::I2C_HZ);
    // The companion chip can come up after the ESP32 (seen at power-on on a V1.4): wait up to 2 s for it, quietly,
    // then let begin() log what it found once.
    for (int i = 0; i < 20 && !panel_mcu::probe(); ++i) delay(100);
    panel_mcu::begin();
    if (!display_init()) {
        Serial.println("deck panel: no display, restarting in 5 s");
        delay(5000);
        esp_restart();
    }
    perf_log::begin();
    touch_init();
    build_screen();
    lv_refr_now(display_lvgl());  // the whole first frame, now, whatever ran before
    // Last, after that frame, so the screen doesn't flash on boot.
    if (!panel_mcu::backlightOn()) Serial.println("deck panel: the backlight may be off");
#ifdef DECK_PANEL_TEST_SCREEN
    Serial.println("deck panel: test screen up");
#else
    wifi_link::begin();  // after the backlight: joining takes seconds and must not hold the first frame
    Serial.println("deck panel: deck view up");
#endif
}

void loop() {
    touch_poll();
#ifdef DECK_PANEL_TEST_SCREEN
    test_screen::show_touch();
#else
    const uint32_t now = millis();
    wifi_link::poll(now);
    g_core.set_network(wifi_link::state(), wifi_link::ip());
    g_udp.poll(wifi_link::state() == deck_core::Network::connected, wifi_link::joins(), now);
    // Until the socket is empty, within the drain's time budget (#636).
    const int read = g_drain.run(g_udp, g_core, now, [] { return static_cast<uint32_t>(millis()); });
    perf_log::tick(now, read, g_drain.too_big());
    if (g_drain.too_big() != g_too_big) {
        g_too_big = g_drain.too_big();
        Serial.printf("deck panel: %lu feed datagrams too big, dropped\n", static_cast<unsigned long>(g_too_big));
    }
    // Read after the drain, so a datagram stamped `now` is never in the future of the render.
    g_core.render(g_screen, millis());
    log_health(now);
    if (g_hold.update(touch_pressed(), g_core.waiting(), now)) wifi_link::forget_and_restart();
#endif
    lv_timer_handler();
    delay(5);
}
