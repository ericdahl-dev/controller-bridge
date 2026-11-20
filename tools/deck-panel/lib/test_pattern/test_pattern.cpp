#include "test_pattern.h"

namespace test_pattern {

std::array<Bar, kBarCount> bars(int width) {
    std::array<Bar, kBarCount> out{};
    // Each edge is rounded from the whole width, so the last bar ends exactly at the edge.
    for (int i = 0; i < kBarCount; ++i) {
        const int left = width * i / kBarCount;
        const int right = width * (i + 1) / kBarCount;
        out[i] = {left, right - left};
    }
    return out;
}

}  // namespace test_pattern
