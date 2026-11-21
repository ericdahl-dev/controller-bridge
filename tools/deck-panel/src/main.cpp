// The deck panel (#490, #620): joins Wi-Fi, listens for DeckBridge's display feed and shows the deck in front, or the
// waiting screen with its address and port. Everything runs on Arduino's loop task: the core isn't thread-safe, so
// the UDP socket is polled here, never read from a callback. Built with DECK_PANEL_TEST_SCREEN (env crowpanel-test),
// it shows the test screen (#615) instead, with no Wi-Fi.
//
// One frame clock (#663, lib/frame_clock): loop() is one frame. It waits for the panel's latch (and, by default, the
// vsync after it, about 1.9 ms later: PANEL_WAKE_AT_VSYNC in display_driver.cpp), reads the feed that came since,
// renders, refreshes once (draw and swap), then does the chores (Wi-Fi, touch, serial) until a guard before the next
// latch. A datagram read after latch N is swapped before N+1 and on glass from N+1: under one scan-out.
#include <Arduino.h>
#include <Wire.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>
#include <lvgl.h>

#include "board_pins.h"
#include "display_driver.h"
#include "frame_clock.h"
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

// Serial's TX ring buffer: a print lands in it and the UART drains it in the background (115200 baud, about 11.5 B a
// millisecond), so no print waits for the wire unless the buffer is full. IDF's TX ring doesn't split an item and
// takes a write in chunks of up to half its size, each with a header, so it holds less than its size: 2 KB keeps the
// perf line (under 640 B), the health line and a few more with room.
// -DPANEL_SERIAL_TX_BYTES=0 goes back to no buffer, to try on the panel.
#ifndef PANEL_SERIAL_TX_BYTES
#define PANEL_SERIAL_TX_BYTES 2048
#endif
constexpr size_t kSerialTxBytes = PANEL_SERIAL_TX_BYTES;
// The chores end this long before the next latch, so the frame's wait starts before it.
constexpr uint32_t kGuardUs = 3000;

uint32_t now_us() { return static_cast<uint32_t>(esp_timer_get_time()); }

#ifndef DECK_PANEL_TEST_SCREEN
/// Whether `until_us` is still ahead; esp_timer's low 32 bits wrap every 71 minutes.
bool time_left(uint32_t until_us) { return static_cast<int32_t>(until_us - now_us()) > 0; }
#endif

frame_clock::Clock g_clock(display_frame_us(), kGuardUs);

// The loop's step, for the perf build's copy line (#663); nothing in the others.
#ifdef PANEL_PERF_LOG
#define MARK(step) display_mark(perf_line::Mark::step)
#else
#define MARK(step) \
    do {           \
    } while (0)
#endif

#ifndef DECK_PANEL_TEST_SCREEN
// Static, not loop() locals: the drain's 512-byte buffer and the view's text stay off the loop task's 8 KB stack.
deck_core::DeckCore g_core;
feed_drain::Drain g_drain;
FeedUdp g_udp;
DeckScreen g_screen;
wifi_setup::HoldReset g_hold;
uint32_t g_too_big = 0;
uint32_t g_health_ms = 0;
int g_read = 0;  // this frame's drain, for the perf build's count

/// Once a minute on serial: the loop task's spare stack and internal RAM, the numbers a long run needs.
void log_health(uint32_t now_ms) {
    constexpr uint32_t kEveryMs = 60000;
    if (now_ms - g_health_ms < kEveryMs) return;
    g_health_ms = now_ms;
#ifdef PANEL_PERF_LOG
    display_note_print(96);  // about the line below
#endif
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

// Experiment arms (#663), all off by default, for the late bounce copies: they split "more PSRAM writes a second" from
// "no idle time on core 1". The feed is still read and rendered every frame; only LVGL's refresh is held back.
//   -DPANEL_DRAW_CAP=N           refresh at most N frames a second of the panel's 30 (e.g. 22, main's rate)
//   -DPANEL_DRAW_SKIP_AFTER_US=N skip the refresh on the frame after one that took longer than N us
//   -DPANEL_YIELD_US=N           after each frame's refresh, block the loop N us (a timer and a semaphore, no spin)
//   -DPANEL_WAKE_DELAY_US=N      start each frame N us after the vsync wake, the loop asleep till then: moves only the
//                                phase. The bounce copy that runs late is the first after the vertical blank, about
//                                3.28 ms after the latch; its preload is issued about 2.4 ms before it, so anything
//                                core 1 does in that gap can evict it. 2500 wakes at about +4.4 ms, past that copy.
#ifndef PANEL_DRAW_CAP
#define PANEL_DRAW_CAP 0
#endif
#ifndef PANEL_DRAW_SKIP_AFTER_US
#define PANEL_DRAW_SKIP_AFTER_US 0
#endif
#ifndef PANEL_YIELD_US
#define PANEL_YIELD_US 0
#endif
#ifndef PANEL_WAKE_DELAY_US
#define PANEL_WAKE_DELAY_US 0
#endif

#if PANEL_YIELD_US > 0 || PANEL_WAKE_DELAY_US > 0
SemaphoreHandle_t g_yield_sem = nullptr;
esp_timer_handle_t g_yield_timer = nullptr;

void yield_done(void*) { xSemaphoreGive(g_yield_sem); }

void yield_begin() {
    g_yield_sem = xSemaphoreCreateBinary();
    const esp_timer_create_args_t args = {yield_done, nullptr, ESP_TIMER_TASK, "yield", false};
    if (g_yield_sem == nullptr || esp_timer_create(&args, &g_yield_timer) != ESP_OK) {
        g_yield_timer = nullptr;
        Serial.println("deck panel: no yield timer; yielding in whole ticks");
    }
    Serial.printf("deck panel: yield %u us after each refresh, wake %u us after the vsync\n", unsigned(PANEL_YIELD_US),
                  unsigned(PANEL_WAKE_DELAY_US));
}

/// Blocks the loop task `us`; core 1 runs its idle task meanwhile.
void yield_for(uint32_t us) {
    if (g_yield_timer != nullptr && esp_timer_start_once(g_yield_timer, us) == ESP_OK) {
        // The timer gives in `us`; the bound only covers a lost give.
        xSemaphoreTake(g_yield_sem, pdMS_TO_TICKS(us / 1000 + 5));
        return;
    }
    vTaskDelay(pdMS_TO_TICKS((us + 999) / 1000));
}
#endif

/// The panel, as the frame clock sees it.
class PanelBoard : public frame_clock::Board {
  public:
    bool wait_latch(uint32_t& count, uint32_t& us) override {
        // Two scan-outs: only a stopped panel misses it, and then the chores still run.
        DisplayLatch latch;
        MARK(wait);
        if (!display_wait_latch(2 * display_frame_us() / 1000, latch)) {
            us = now_us();
            return false;
        }
#if PANEL_WAKE_DELAY_US > 0
        yield_for(PANEL_WAKE_DELAY_US);  // still "wait" on the copy line
#endif
        count = latch.count;
        us = latch.us;
        return true;
    }

    void read_feed() override {
        MARK(read);
#ifndef DECK_PANEL_TEST_SCREEN
        // At the frame's start (the vsync after the latch, by default): until the socket is empty, within the
        // drain's time budget (#636).
        g_read = g_drain.run(g_udp, g_core, millis(), [] { return static_cast<uint32_t>(millis()); });
#endif
    }

    void render() override {
        MARK(render);
#ifdef DECK_PANEL_TEST_SCREEN
        test_screen::show_touch();
#else
        // Read after the drain, so a datagram stamped then is never in the future of the render.
        g_core.render(g_screen, millis());
#endif
    }

    void refresh() override {
        bool draw = true;
#if PANEL_DRAW_CAP > 0
        // Credit of PANEL_DRAW_CAP a frame, one refresh per 30.
        if (draw_credit_ + PANEL_DRAW_CAP >= 30) {
            draw_credit_ = draw_credit_ + PANEL_DRAW_CAP - 30;
        } else {
            draw_credit_ += PANEL_DRAW_CAP;
            draw = false;
        }
#endif
#if PANEL_DRAW_SKIP_AFTER_US > 0
        if (last_long_) draw = false;
        last_long_ = false;
#endif
        if (draw) {
            MARK(refresh);
            const uint32_t start = now_us();
            display_refresh();
            const uint32_t took = now_us() - start;
#if PANEL_DRAW_SKIP_AFTER_US > 0
            last_long_ = took > PANEL_DRAW_SKIP_AFTER_US;
#endif
            (void)took;
        }
#if PANEL_YIELD_US > 0
        MARK(other);  // the yield: the copy line's "other" step
        yield_for(PANEL_YIELD_US);
#endif
    }

    void chores(uint32_t until_us) override {
#ifdef DECK_PANEL_TEST_SCREEN
        (void)until_us;
        MARK(touch);
        touch_poll();
        MARK(lvgl);
        lv_timer_handler();
#else
        const uint32_t now = millis();
        // Every frame: these can't wait, and the first can't be bounded (setup's web server, a join, a scan).
        MARK(wifi);
        wifi_link::poll(now);
        g_core.set_network(wifi_link::state(), wifi_link::ip());
        MARK(udp);
        g_udp.poll(wifi_link::state() == deck_core::Network::connected, wifi_link::joins(), now);
        // Touch only off the deck: the waiting, joining and setup screens, where the hold reset lives. On the deck
        // touch_pressed() keeps the last waiting-screen state, which only ever stops a hold (HoldReset), and the
        // first poll back on the waiting screen comes before the hold sees it.
        MARK(touch);
        if (g_core.waiting() && time_left(until_us)) touch_poll();
        if (g_hold.update(touch_pressed(), g_core.waiting(), now)) wifi_link::forget_and_restart();
        // LVGL's other timers: the touch's input device, animations. Its refresh timer is gone (display_init).
        MARK(lvgl);
        lv_timer_handler();
        MARK(perf);
        // Serial last, and only with time left; what waits prints at a later frame.
        const bool may_print = time_left(until_us);
        perf_log::tick(now, g_read, g_drain.too_big(), may_print, g_clock);
        g_read = 0;
        if (!may_print) return;
        if (g_drain.too_big() != g_too_big) {
            g_too_big = g_drain.too_big();
            Serial.printf("deck panel: %lu feed datagrams too big, dropped\n", static_cast<unsigned long>(g_too_big));
        }
        log_health(now);
#endif
    }

  private:
#if PANEL_DRAW_CAP > 0
    uint32_t draw_credit_ = 0;
#endif
#if PANEL_DRAW_SKIP_AFTER_US > 0
    bool last_long_ = false;
#endif
};

PanelBoard g_board;

}  // namespace

void setup() {
    // Before begin(): the buffer can't be set after.
    const bool tx_buffered = kSerialTxBytes == 0 || Serial.setTxBufferSize(kSerialTxBytes) == kSerialTxBytes;
    Serial.begin(115200);
    if (!tx_buffered) Serial.println("deck panel: no serial TX buffer; prints may hold a frame");
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
    display_refresh();  // the whole first frame, now, whatever ran before
#if PANEL_YIELD_US > 0 || PANEL_WAKE_DELAY_US > 0
    yield_begin();
#endif
    // Last, after that frame, so the screen doesn't flash on boot.
    if (!panel_mcu::backlightOn()) Serial.println("deck panel: the backlight may be off");
#ifdef DECK_PANEL_TEST_SCREEN
    Serial.println("deck panel: test screen up");
#else
    wifi_link::begin();  // after the backlight: joining takes seconds and must not hold the first frame
    Serial.println("deck panel: deck view up");
#endif
}

// One frame (lib/frame_clock): no delay; the wait for the latch is the loop's only pause.
void loop() { g_clock.step(g_board); }
