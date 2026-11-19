// Design B (#165) as JogDisplayRenderer draws it, measured in its pixels: y down, (0, 0) the top-left corner, a pixel's
// center at +0.5. Edges are anti-aliased by coverage: a pixel is blended toward a shape by how much of it the shape
// covers, estimated from the signed distance between the pixel's center and the shape's edge.
#include "draw.h"
#include "font_header.h"

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

/// How much of a pixel lies inside a straight edge, from the signed distance of its center to the edge (positive
/// inside) and the edge's unit normal: the exact area of the pixel square on the inside. A 45° edge ramps over 1.41 px,
/// not 1, which a plain distance ramp gets visibly wrong on the chip.
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
            float nx = r > 0.0f ? dx / r : 1.0f, ny = r > 0.0f ? dy / r : 0.0f;
            float band = edge_cover(RING_OUTER - r, nx, ny) + edge_cover(r - RING_INNER, nx, ny) - 1.0f;
            if (band <= 0.0f) continue;
            // Each step turns the point a quarter turn back, so beat b's section lands where beat 1's is.
            float px = dx, py = dy;
            for (int beat = 0; beat < 4; beat++) {
                // The edge normals turn with the point, so they are taken in its turned frame.
                float cover = band * edge_cover(px * start_nx + py * start_ny, start_nx, start_ny)
                    * edge_cover(px * end_nx + py * end_ny, end_nx, end_ny);
                dfw_pixel *p = &frame[y * DFW_SIZE + x];
                *p = blend(*p, beat == 0 ? DOWNBEAT_OFF : BEAT_OFF, cover);
                float t = px;
                px = py;
                py = -t;
            }
        }
    }
}

/// Rounds down; the coordinates drawn are within the frame, well inside int range.
static int floor_int(float x) {
    if (x < -1000.0f) x = -1000.0f;
    if (x > 1000.0f) x = 1000.0f;
    int i = (int)x;
    return (float)i > x ? i - 1 : i;
}

static const dfw_glyph *glyph(const dfw_face *face, char code) {
    for (uint8_t i = 0; i < face->count; i++)
        if (face->glyphs[i].code == code) return &face->glyphs[i];
    return 0;
}

/// A glyph's coverage blended in the face's ink, with its origin at x on the face's baseline row. CoreText snaps the
/// origin down to a half pixel; the bitmaps are kept at both halves.
static void draw_glyph(dfw_pixel *frame, const dfw_face *face, const dfw_glyph *g, float x, int baseline_row) {
    int half = floor_int(x * 2.0f);
    const dfw_glyph_bitmap *b = &g->phase[half & 1];
    int left = (half >> 1) + b->left, top = baseline_row + b->top;
    for (int row = 0; row < b->height; row++) {
        int y = top + row;
        if (y < 0 || y >= DFW_SIZE) continue;
        for (int col = 0; col < b->width; col++) {
            int px = left + col;
            if (px < 0 || px >= DFW_SIZE) continue;
            dfw_pixel *p = &frame[y * DFW_SIZE + px];
            *p = blend(*p, face->ink, (float)b->coverage[row * b->width + col] / 255.0f);
        }
    }
}

/// The face's baseline row for a line whose box is centered on `middle`, as the renderer centers it. The bitmaps were
/// rasterized at the fraction the header's middles give.
static int baseline_row(const dfw_face *face, float middle) {
    return floor_int(middle + (face->ascent - face->descent) / 2.0f);
}

/// A filled circle, anti-aliased.
static void disc(dfw_pixel *frame, float cx, float cy, float radius, dfw_pixel color) {
    for (int y = floor_int(cy - radius - 1.0f); y <= floor_int(cy + radius + 1.0f); y++) {
        if (y < 0 || y >= DFW_SIZE) continue;
        float dy = (float)y + 0.5f - cy;
        for (int x = floor_int(cx - radius - 1.0f); x <= floor_int(cx + radius + 1.0f); x++) {
            if (x < 0 || x >= DFW_SIZE) continue;
            float dx = (float)x + 0.5f - cx;
            dfw_pixel *p = &frame[y * DFW_SIZE + x];
            float r = root(dx * dx + dy * dy);
            float cover = r > 0.0f ? edge_cover(radius - r, dx / r, dy / r) : 1.0f;
            *p = blend(*p, color, cover);
        }
    }
}

#define CHIP 26.0f
#define HEADER_MIDDLE 37.0f

/// The deck chip, a 26 px circle in the deck color with the number in the ground color, centered at y 37.
static void header(dfw_pixel *frame, const dfw_deck_state *deck) {
    float left = CENTER - CHIP / 2.0f;
    dfw_pixel color = (dfw_pixel)deck->r << 16 | (dfw_pixel)deck->g << 8 | deck->b;
    disc(frame, left + CHIP / 2.0f, HEADER_MIDDLE, CHIP / 2.0f, color);
    // A number outside 1-4 has no glyph: the chip alone.
    const dfw_glyph *number = glyph(&number_face, (char)('0' + (deck->number <= 9 ? deck->number : 0)));
    if (number && deck->number >= 1 && deck->number <= 4)
        draw_glyph(frame, &number_face, number, left + CHIP / 2.0f - number->advance / 2.0f,
                   baseline_row(&number_face, HEADER_MIDDLE));
}

void dfw_draw(dfw_pixel *frame, const dfw_deck_state *deck) {
    for (int i = 0; i < DFW_SIZE * DFW_SIZE; i++) frame[i] = GROUND;
    ring(frame);
    header(frame, deck);
}
