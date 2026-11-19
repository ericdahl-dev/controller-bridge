// The progress ring's geometry (#524, #558): the band's shape and its anti-aliasing, shared by the table generator
// (gen/band_table_gen.c, on the host) and draw_band.c (on the chip), so the table holds exactly what draw_band.c
// worked out per pixel before it had one. Float only, no libm.
#ifndef DFW_BAND_GEOMETRY_H
#define DFW_BAND_GEOMETRY_H
#include "dfw.h"

#define CENTER 99.0f
#define BAND_INNER 103.0f
#define BAND_OUTER 107.0f
#define BAND_TRACK 0x4A4A4Au
/// Under the ring: the frame's ground inside the 198 square, the panel's black outside it.
#define GROUND 0x0B0B0Bu
#define PANEL 0x000000u
/// The time's white (the blink's other half) and the warning's red, as draw_live.c's.
#define WARNING_WHITE 0xEDEDEAu
#define WARNING_RED 0xFF3B30u
/// The band's reach either side, for the frame (x, y) loops: center ± (outer + 1).
#define REACH 109

/// The band's annulus as far as any of its pixels reach (r 102-108, with half a pixel to spare): every pixel of it
/// outside the square is the band's in the layer, black where the ring doesn't cover it.
#define CLEAR_INNER 101.5f
#define CLEAR_OUTER 108.5f

/// A square root by Newton's method from a bit-level first guess, as draw.c's. No libm on the chip.
static inline float root(float x) {
    if (x <= 0.0f) return 0.0f;
    union { float f; uint32_t u; } v = { x };
    v.u = (v.u >> 1) + 0x1FBD1DF5u;
    float r = v.f;
    for (int i = 0; i < 3; i++) r = 0.5f * (r + x / r);
    return r;
}

static inline float clamp01(float x) { return x < 0.0f ? 0.0f : x > 1.0f ? 1.0f : x; }

/// How much of a pixel lies inside a straight edge, from the signed distance of its center to the edge (positive
/// inside) and the edge's unit normal: the exact area of the pixel square on the inside, as draw.c's.
static inline float edge_cover(float distance, float nx, float ny) {
    float a = nx < 0.0f ? -nx : nx, b = ny < 0.0f ? -ny : ny;
    if (a < b) { float t = a; a = b; b = t; }
    float s = distance + (a + b) / 2.0f;
    if (s <= 0.0f) return 0.0f;
    if (s >= a + b) return 1.0f;
    if (b < 1e-6f) return clamp01(s / a);
    if (s < b) return s * s / (2.0f * a * b);
    if (s < a) return (s - b / 2.0f) / a;
    float t = a + b - s;
    return 1.0f - t * t / (2.0f * a * b);
}

/// `under` moved toward `over` by `cover` (0-1), per channel, rounded.
static inline dfw_pixel blend(dfw_pixel under, dfw_pixel over, float cover) {
    if (cover <= 0.0f) return under;
    if (cover >= 1.0f) return over;
    dfw_pixel out = 0;
    for (int shift = 0; shift <= 16; shift += 8) {
        float a = (float)(under >> shift & 0xFFu), b = (float)(over >> shift & 0xFFu);
        float c = a + (b - a) * cover + 0.5f;
        out |= (dfw_pixel)(c < 0.0f ? 0.0f : c > 255.0f ? 255.0f : c) << shift;
    }
    return out;
}

static inline int in_frame(int x, int y) { return x >= 0 && x < DFW_SIZE && y >= 0 && y < DFW_SIZE; }

/// The ring's shape at frame pixel (x, y), whatever its progress: how much of the pixel the band covers (0 when none),
/// how much lies clockwise of the 12 o'clock ray (the fill's start edge), and the track blended over what lies under it
/// there (the frame's ground in the square, the panel's black outside). Returns whether the band covers any of it.
static inline int band_shape(int x, int y, float *band, float *start, dfw_pixel *track) {
    float dx = (float)x + 0.5f - CENTER, dy = (float)y + 0.5f - CENTER;
    float d2 = dx * dx + dy * dy;
    *band = 0.0f;
    *start = 0.0f;
    *track = in_frame(x, y) ? GROUND : PANEL;
    if (d2 > (BAND_OUTER + 1.0f) * (BAND_OUTER + 1.0f) || d2 < (BAND_INNER - 1.0f) * (BAND_INNER - 1.0f)) return 0;
    float r = root(d2), nx = dx / r, ny = dy / r;
    float cover = edge_cover(BAND_OUTER - r, nx, ny) + edge_cover(r - BAND_INNER, nx, ny) - 1.0f;
    if (cover <= 0.0f) return 0;
    *band = cover;
    *start = edge_cover(dx, 1.0f, 0.0f);
    *track = blend(*track, BAND_TRACK, cover);
    return 1;
}

/// Whether frame pixel (x, y) is in the band's clear annulus: dfw_draw_band gives every one outside the square a value.
static inline int band_clear(int x, int y) {
    float dx = (float)x + 0.5f - CENTER, dy = (float)y + 0.5f - CENTER, d2 = dx * dx + dy * dy;
    return d2 >= CLEAR_INNER * CLEAR_INNER && d2 <= CLEAR_OUTER * CLEAR_OUTER;
}

#endif
