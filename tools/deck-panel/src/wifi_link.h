// The panel's Wi-Fi (#620): a station on the network named at build time (wifi_secrets.py), with no blocking waits.
// Polled from the loop task, which reports its state to the core.
#pragma once

#include <cstdint>

#include "deck_core.h"

namespace wifi_link {

/// Whether the build has a network name: false shows "Wi-Fi isn't set".
bool configured();

/// Starts joining, if the build has credentials. Call once, after the first frame.
void begin();

/// Reads the station's state; call every loop. Cheap: the address is read at most twice a second.
void poll(uint32_t now_ms);

deck_core::Network state();

/// The panel's IPv4 address, dotted; "" unless connected.
const char* ip();

/// Counts connections: changes each time the station (re)joins, so the UDP socket knows to open again.
uint32_t joins();

}  // namespace wifi_link
