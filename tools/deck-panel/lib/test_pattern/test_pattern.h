// The test screen's color bars (#615). Kept free of Arduino and LVGL so it's host-tested.
#pragma once

#include <array>
#include <cstdint>

namespace test_pattern {

struct Bar {
    int x;
    int width;
};

constexpr int kBarCount = 8;

std::array<Bar, kBarCount> bars(int width);

}  // namespace test_pattern
