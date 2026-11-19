// The live elements (#459) as JogDisplayRenderer's simulator image draws them over design B, in its pixels: y down,
// (0, 0) the top-left corner, a pixel's center at +0.5. Anti-aliased by coverage as draw.c is; its helpers are static
// there, so the few this needs are repeated here.
#include "draw_live.h"

#define GROUND 0x0B0B0Bu
#define LIVE 0x00FF48u

#define CENTER 99.0f
#define RING_OUTER 95.0f
#define RING_INNER 85.0f
#define RING_GAP 7.0f

/// A square root by Newton's method from a bit-level first guess, as draw.c's. No libm on the chip.
static float root(float x) {
    if (x <= 0.0f) return 0.0f;
    union { float f; uint32_t u; } v = { x };
    v.u = (v.u >> 1) + 0x1FBD1DF5u;
    float r = v.f;
    for (int i = 0; i < 3; i++) r = 0.5f * (r + x / r);
    return r;
}

static float clamp01(float x) { return x < 0.0f ? 0.0f : x > 1.0f ? 1.0f : x; }

/// How much of a pixel lies inside a straight edge, from the signed distance of its center to the edge (positive
/// inside) and the edge's unit normal: the exact area of the pixel square on the inside, as draw.c's.
static float edge_cover(float distance, float nx, float ny) {
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
static dfw_pixel blend(dfw_pixel under, dfw_pixel over, float cover) {
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

/// sin and cos of a small angle by their series; ample for the ring's half gap (0.04 rad).
static void small_sin_cos(float a, float *s, float *c) {
    float a2 = a * a;
    *s = a * (1.0f - a2 / 6.0f * (1.0f - a2 / 20.0f));
    *c = 1.0f - a2 / 2.0f * (1.0f - a2 / 12.0f);
}

/// Beat `beat`'s (1-4) section in the live green. Swift fills the lit section once over the ground, so it is drawn
/// from the ground here too, not over the unlit section ring() left: that would leave the unlit color in its edges.
/// The sections and the ground are all there is in the band, so the result is Swift's.
static void lit_section(dfw_pixel *frame, int beat) {
    float s, c;
    small_sin_cos(RING_GAP / ((RING_OUTER + RING_INNER) / 2.0f) / 2.0f, &s, &c);
    // Beat 1's edges, as normals pointing into the section (see draw.c's ring()).
    const float start_nx = c, start_ny = s, end_nx = -s, end_ny = -c;
    for (int y = 0; y < DFW_SIZE; y++) {
        float dy = (float)y + 0.5f - CENTER;
        for (int x = 0; x < DFW_SIZE; x++) {
            float dx = (float)x + 0.5f - CENTER;
            float d2 = dx * dx + dy * dy;
            if (d2 > (RING_OUTER + 1.0f) * (RING_OUTER + 1.0f) || d2 < (RING_INNER - 1.0f) * (RING_INNER - 1.0f)) continue;
            float r = root(d2);
            float nx = r > 0.0f ? dx / r : 1.0f, ny = r > 0.0f ? dy / r : 0.0f;
            float band = edge_cover(RING_OUTER - r, nx, ny) + edge_cover(r - RING_INNER, nx, ny) - 1.0f;
            if (band <= 0.0f) continue;
            // A quarter turn back per beat after the first lands the point where beat 1's section is.
            float px = dx, py = dy;
            for (int step = 1; step < beat; step++) {
                float t = px;
                px = py;
                py = -t;
            }
            float cover = band * edge_cover(px * start_nx + py * start_ny, start_nx, start_ny)
                * edge_cover(px * end_nx + py * end_ny, end_nx, end_ny);
            if (cover > 0.0f) frame[y * DFW_SIZE + x] = blend(GROUND, LIVE, cover);
        }
    }
}

void dfw_draw_live(dfw_pixel *frame, const dfw_unit *unit) {
    if (dfw_stale(unit)) return;
    if (unit->beat >= 1 && unit->beat <= 4) lit_section(frame, unit->beat);
}
