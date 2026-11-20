// Hold-to-reset (#622): a finger held kHoldMs on the waiting screen forgets the saved Wi-Fi. Kept free of Arduino so
// it's host-tested; the loop feeds it the touch state and whether the waiting screen is up.
#pragma once

#include <cstdint>

namespace wifi_setup {

class HoldReset {
  public:
    static constexpr uint32_t kHoldMs = 5000;

    // True once, when a hold that began on the waiting screen reaches kHoldMs; letting go re-arms it.
    bool update(bool pressed, bool waiting_screen, uint32_t now_ms);

  private:
    bool holding_ = false;  // a hold on the waiting screen is being timed
    bool fired_ = false;    // this press already fired
    uint32_t since_ms_ = 0;
};

}  // namespace wifi_setup
