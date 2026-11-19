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
/// origin down to 1/phases of a pixel; the bitmaps are kept at each of those phases.
static void draw_glyph(dfw_pixel *frame, const dfw_face *face, const dfw_glyph *g, float x, int baseline_row) {
    int whole = floor_int(x);
    int phase = floor_int((x - (float)whole) * (float)face->phases);
    if (phase < 0) phase = 0;
    if (phase >= face->phases || phase >= DFW_PHASES_MAX) phase = face->phases - 1;
    const dfw_glyph_bitmap *b = &g->phase[phase];
    if (!b->coverage) return;
    int left = whole + b->left, top = baseline_row + b->top;
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

/// A rounded rectangle's outline, `width` wide, centered on the path through (x, y, w, h) with corner radius `radius`.
/// Coverage comes from the signed distance to the path and the direction it is measured in.
static void rounded_outline(dfw_pixel *frame, float x, float y, float w, float h, float radius, float width,
                            dfw_pixel color) {
    float cx = x + w / 2.0f, cy = y + h / 2.0f, hx = w / 2.0f - radius, hy = h / 2.0f - radius;
    for (int py = floor_int(y - width - 1.0f); py <= floor_int(y + h + width + 1.0f); py++) {
        if (py < 0 || py >= DFW_SIZE) continue;
        for (int px = floor_int(x - width - 1.0f); px <= floor_int(x + w + width + 1.0f); px++) {
            if (px < 0 || px >= DFW_SIZE) continue;
            float dx = (float)px + 0.5f - cx, dy = (float)py + 0.5f - cy;
            float qx = (dx < 0.0f ? -dx : dx) - hx, qy = (dy < 0.0f ? -dy : dy) - hy;
            float d, nx, ny;
            if (qx > 0.0f && qy > 0.0f) {
                // Beside a corner: the distance to its arc, along the line from the arc's center.
                float r = root(qx * qx + qy * qy);
                d = r - radius;
                nx = qx / r;
                ny = qy / r;
            } else if (qx > qy) {
                d = qx - radius;
                nx = 1.0f;
                ny = 0.0f;
            } else {
                d = qy - radius;
                nx = 0.0f;
                ny = 1.0f;
            }
            float cover = edge_cover(width / 2.0f - d, nx, ny) + edge_cover(width / 2.0f + d, nx, ny) - 1.0f;
            dfw_pixel *p = &frame[py * DFW_SIZE + px];
            *p = blend(*p, color, cover);
        }
    }
}

/// A line's width as CoreText lays it out: each glyph's advance plus the tracking, the last one's too.
static float line_width(const dfw_face *face, const char *text) {
    float width = 0.0f;
    for (int i = 0; text[i] && i < 8; i++) {
        const dfw_glyph *g = glyph(face, text[i]);
        if (g) width += g->advance + face->tracking;
    }
    return width;
}

static void draw_line(dfw_pixel *frame, const dfw_face *face, const char *text, float x, float middle) {
    int row = baseline_row(face, middle);
    for (int i = 0; text[i] && i < 8; i++) {
        const dfw_glyph *g = glyph(face, text[i]);
        if (!g) continue;
        draw_glyph(frame, face, g, x, row);
        x += g->advance + face->tracking;
    }
}

#define CHIP 26.0f
#define BADGE_GAP 6.0f
#define BADGE_HEIGHT 22.0f
#define BADGE_PADDING 15.0f
#define BADGE_STROKE 1.5f
#define BADGE_CORNER 4.25f
#define BADGE_OUTLINE 0xBDBDBDu
#define HEADER_MIDDLE 37.0f

/// The player badge for each player (#209): none for empty (0) and other (5), whose name the deck message doesn't carry.
static const char *const badges[] = { 0, "TRK", "OSC", "MIDI", "SEQ", 0 };

/// The deck chip (a 26 px circle in the deck color, the number in the ground color) and the player badge, centered
/// together at y 37. The badge is its label in a 1.5 px outline, 22 px tall, 6 px after the chip.
static void header(dfw_pixel *frame, const dfw_deck_state *deck) {
    const char *label = deck->player < sizeof badges / sizeof badges[0] ? badges[deck->player] : 0;
    float text = label ? line_width(&badge_face, label) : 0.0f, badge = text + BADGE_PADDING;
    float left = CENTER - (CHIP + (label ? BADGE_GAP + badge : 0.0f)) / 2.0f;
    dfw_pixel color = (dfw_pixel)deck->r << 16 | (dfw_pixel)deck->g << 8 | deck->b;
    disc(frame, left + CHIP / 2.0f, HEADER_MIDDLE, CHIP / 2.0f, color);
    // A number outside 1-4 has no glyph: the chip alone.
    const dfw_glyph *number = glyph(&number_face, (char)('0' + (deck->number <= 9 ? deck->number : 0)));
    if (number && deck->number >= 1 && deck->number <= 4)
        draw_glyph(frame, &number_face, number, left + CHIP / 2.0f - number->advance / 2.0f,
                   baseline_row(&number_face, HEADER_MIDDLE));
    if (!label) return;
    float inset = BADGE_STROKE / 2.0f, x = left + CHIP + BADGE_GAP;
    rounded_outline(frame, x + inset, HEADER_MIDDLE - BADGE_HEIGHT / 2.0f + inset, badge - 2.0f * inset,
                    BADGE_HEIGHT - 2.0f * inset, BADGE_CORNER, BADGE_STROKE, BADGE_OUTLINE);
    draw_line(frame, &badge_face, label, x + badge / 2.0f - text / 2.0f, HEADER_MIDDLE + 0.5f);
}

void dfw_draw(dfw_pixel *frame, const dfw_unit *unit) {
    for (int i = 0; i < DFW_SIZE * DFW_SIZE; i++) frame[i] = GROUND;
    ring(frame);
    header(frame, &unit->deck);
}
