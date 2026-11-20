// Text fitted to the panel's font (#620): LVGL's built-in Montserrat has printable ASCII only, so anything else would
// draw as an empty box. Until #621's fonts with Latin coverage, accented Latin letters lose their accents, "…" is
// "...", and any other character is "?".
#pragma once

#include <cstddef>

namespace font_fallback {

/// `text` (valid UTF-8) fitted into `out`, at most `size - 1` bytes and a NUL, cut between characters.
void fit(const char* text, char* out, size_t size);

}  // namespace font_fallback
