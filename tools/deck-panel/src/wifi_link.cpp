#include "wifi_link.h"

#include <Arduino.h>
#include <WiFi.h>

#include <cstdio>
#include <cstring>

// Generated at build time from a file outside the repo (wifi_secrets.py); only this file includes it.
#include "wifi_secrets.h"

namespace wifi_link {

namespace {

using deck_core::Network;

/// The core retries most disconnects itself, but not an AP that refused the password after the first try, which a
/// router coming back can do: then a kick this long after the last one.
constexpr uint32_t kKickAfterMs = 30000;
constexpr uint32_t kAddressEveryMs = 500;

Network g_state = Network::setup;
char g_ip[16] = "";
uint32_t g_address = 0;
uint32_t g_joins = 0;
uint32_t g_down_since_ms = 0;
uint32_t g_address_read_ms = 0;
bool g_started = false;

void set_address(uint32_t address) {
    g_address = address;
    if (address == 0) {
        g_ip[0] = 0;
        return;
    }
    // IPAddress keeps the first octet in the low byte.
    std::snprintf(g_ip, sizeof g_ip, "%u.%u.%u.%u", unsigned(address & 0xFF), unsigned(address >> 8 & 0xFF),
                  unsigned(address >> 16 & 0xFF), unsigned(address >> 24));
}

/// Starts the station; false if the driver didn't start, and poll() tries again.
bool start() {
    WiFi.persistent(false);  // the credentials stay in the image only, not copied into NVS too
    if (!WiFi.mode(WIFI_STA)) {
        Serial.println("deck panel: Wi-Fi didn't start; retrying");
        return false;
    }
    WiFi.setAutoReconnect(true);
    // Modem sleep holds received packets up to a beacon interval (~100 ms); the panel is on mains power.
    if (!WiFi.setSleep(false)) Serial.println("deck panel: Wi-Fi sleep stays on");
    if (WiFi.begin(DECK_PANEL_WIFI_SSID, DECK_PANEL_WIFI_PASSWORD) == WL_CONNECT_FAILED) {
        Serial.println("deck panel: Wi-Fi join didn't start; retrying");
    }
    Serial.println("deck panel: joining Wi-Fi");
    return true;
}

}  // namespace

bool configured() { return DECK_PANEL_WIFI_SSID[0] != 0; }

void begin() {
    if (!configured()) {
        Serial.println("deck panel: built without Wi-Fi");
        return;
    }
    // Joining from here on, even if the driver fails to start: "Wi-Fi isn't set" would send the owner to the wrong fix.
    g_state = Network::joining;
    g_down_since_ms = millis();
    g_started = start();
}

void poll(uint32_t now_ms) {
    if (g_state == Network::setup) return;
    if (!g_started) {
        if (now_ms - g_down_since_ms < kKickAfterMs) return;
        g_down_since_ms = now_ms;
        g_started = start();
        return;
    }
    const bool up = WiFi.status() == WL_CONNECTED;
    if (up) {
        if (g_state != Network::connected || now_ms - g_address_read_ms >= kAddressEveryMs) {
            g_address_read_ms = now_ms;
            const uint32_t address = static_cast<uint32_t>(WiFi.localIP());
            if (address == 0) return;  // connected but no address yet: still joining
            if (g_state != Network::connected) {
                ++g_joins;
                g_state = Network::connected;
                set_address(address);
                Serial.printf("deck panel: on Wi-Fi at %s, feed port %u\n", g_ip,
                              unsigned(deck_core::DeckCore::kFeedPort));
            } else if (address != g_address) {
                set_address(address);
                Serial.printf("deck panel: address now %s\n", g_ip);
            }
        }
        return;
    }
    if (g_state == Network::connected) {
        g_state = Network::joining;
        set_address(0);
        g_down_since_ms = now_ms;
        Serial.println("deck panel: Wi-Fi lost, rejoining");
    }
    if (now_ms - g_down_since_ms >= kKickAfterMs) {
        g_down_since_ms = now_ms;
        if (!WiFi.reconnect()) Serial.println("deck panel: Wi-Fi rejoin didn't start");
    }
}

Network state() { return g_state; }

const char* ip() { return g_ip; }

uint32_t joins() { return g_joins; }

}  // namespace wifi_link
