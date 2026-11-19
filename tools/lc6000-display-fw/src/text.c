#include "text.h"

#include "font_text.h"

const dfw_text_face *const dfw_title26 = &title26_face, *const dfw_title20 = &title20_face,
                    *const dfw_caption16 = &caption16_face, *const dfw_mono22 = &mono22_face;

enum { LIG_FF, LIG_FI, LIG_FL, LIG_TT };

/// The glyph at codes[*i], taking a ligature's pair as one (greedy, as CoreText: "ffi" is ff then i), and moving *i
/// past what it took. DFW_NO_GLYPH for a code that draws nothing.
static uint8_t next_glyph(const dfw_text_face *face, const uint8_t *codes, size_t count, size_t *i) {
    uint8_t code = codes[*i];
    (*i)++;
    if (*i < count) {
        uint8_t after = codes[*i];
        int lig = -1;
        if (code == 'f') lig = after == 'f' ? LIG_FF : after == 'i' ? LIG_FI : after == 'l' ? LIG_FL : -1;
        if (code == 't' && after == 't') lig = LIG_TT;
        if (lig >= 0 && face->ligature[lig] != DFW_NO_GLYPH) {
            (*i)++;
            return face->ligature[lig];
        }
    }
    return face->glyph_of[code];
}

/// The kern between two glyphs, in font units: a binary search of the sorted pairs.
static int kern(const dfw_text_face *face, uint8_t left, uint8_t right) {
    uint16_t pair = (uint16_t)(left << 8 | right);
    size_t low = 0, high = face->kern_count;
    while (low < high) {
        size_t mid = (low + high) / 2;
        if (face->kerns[mid].pair == pair) return face->kerns[mid].units;
        if (face->kerns[mid].pair < pair) low = mid + 1; else high = mid;
    }
    return 0;
}

float dfw_text_size(const dfw_text_face *face) { return face->size; }
uint16_t dfw_text_units_per_em(const dfw_text_face *face) { return face->units_per_em; }

float dfw_text_width(const dfw_text_face *face, const uint8_t *codes, size_t count, int tracked) {
    return (float)dfw_text_units(face, codes, count, tracked) * face->size / (float)face->units_per_em;
}

int32_t dfw_text_units(const dfw_text_face *face, const uint8_t *codes, size_t count, int tracked) {
    // Font units, summed exactly, then scaled once by the caller: a fit decided by <= can't turn on rounding.
    int32_t units = 0;
    int previous = -1;
    for (size_t i = 0; i < count;) {
        uint8_t glyph = next_glyph(face, codes, count, &i);
        if (glyph == DFW_NO_GLYPH) continue;
        units += face->glyphs[glyph].advance;
        if (tracked) {
            units += face->tracking;
            if (previous >= 0) units += kern(face, (uint8_t)previous, glyph);
        }
        previous = glyph;
    }
    return units;
}
