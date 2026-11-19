// Design B (#165) as JogDisplayRenderer draws it, measured in its pixels: y down, (0, 0) the top-left corner, a pixel's
// center at +0.5. Edges are anti-aliased by coverage: a pixel is blended toward a shape by how much of it the shape
// covers, estimated from the signed distance between the pixel's center and the shape's edge.
#include "draw.h"

#define GROUND 0x0B0B0Bu
#define DOWNBEAT_OFF 0x5A5A5Au
#define BEAT_OFF 0x2C2C2Cu

#define CENTER 99.0f
#define RING_OUTER 95.0f
#define RING_INNER 85.0f
/// The gap between beat sections, measured at mid-band.
#define RING_GAP 7.0f

/// A square root by Newton's method from a bit-level first guess: three steps take it to float precision for the
/// values drawn here (0 to 2·198²). No libm on the chip.
static float root(float x) {
    if (x <= 0.0f) return 0.0f;
    union { float f; uint32_t u; } v = { x };
    v.u = (v.u >> 1) + 0x1FBD1DF5u;
    float r = v.f;
    for (int i = 0; i < 3; i++) r = 0.5f * (r + x / r);
    return r;
}

static float clamp01(float x) { return x < 0.0f ? 0.0f : x > 1.0f ? 1.0f : x; }

/// How much of a pixel lies inside an edge, from the signed distance of its center to the edge (positive inside).
static float inside(float distance) { return clamp01(distance + 0.5f); }

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

/// The four beat sections, clockwise from 12 o'clock, beat 1 a step brighter. Angles run from 12 o'clock clockwise,
/// which on screen (y down) is the direction (sin a, −cos a), and clockwise from it is (cos a, sin a). Each section is
/// under half a turn, so it is the band between the two radii cut by two half-planes through the center.
static void ring(dfw_pixel *frame) {
    float s, c;
    small_sin_cos(RING_GAP / ((RING_OUTER + RING_INNER) / 2.0f) / 2.0f, &s, &c);
    // Beat 1's edges, at half and π/2 − half, as normals pointing into the section.
    const float start_nx = c, start_ny = s, end_nx = -s, end_ny = -c;
    for (int y = 0; y < DFW_SIZE; y++) {
        float dy = (float)y + 0.5f - CENTER;
        for (int x = 0; x < DFW_SIZE; x++) {
            float dx = (float)x + 0.5f - CENTER;
            float d2 = dx * dx + dy * dy;
            if (d2 > (RING_OUTER + 1.0f) * (RING_OUTER + 1.0f) || d2 < (RING_INNER - 1.0f) * (RING_INNER - 1.0f)) continue;
            float r = root(d2);
            float band = inside(RING_OUTER - r) + inside(r - RING_INNER) - 1.0f;
            if (band <= 0.0f) continue;
            // Each step turns the point a quarter turn back, so beat b's section lands where beat 1's is.
            float px = dx, py = dy;
            for (int beat = 0; beat < 4; beat++) {
                float cover = band * inside(px * start_nx + py * start_ny) * inside(px * end_nx + py * end_ny);
                dfw_pixel *p = &frame[y * DFW_SIZE + x];
                *p = blend(*p, beat == 0 ? DOWNBEAT_OFF : BEAT_OFF, cover);
                float t = px;
                px = py;
                py = -t;
            }
        }
    }
}

void dfw_draw(dfw_pixel *frame, const dfw_deck_state *deck) {
    (void)deck;
    for (int i = 0; i < DFW_SIZE * DFW_SIZE; i++) frame[i] = GROUND;
    ring(frame);
}
