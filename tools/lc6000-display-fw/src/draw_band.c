// The progress ring in the panel's band outside the frame (#524), as JogDisplayRenderer.drawnImage draws it: r 103-107
// round the frame's center (99, 99 in the frame's pixels, a pixel's center at +0.5), a 0x4A4A4A track all round and the
// fill clockwise from 12 o'clock in the deck color, or the warning's red or white. Anti-aliased by coverage as
// draw_live.c is; its helpers are static there, so the few this needs are repeated here. No state of its own.
#include "draw_band.h"

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

/// sin and cos of `turns` (0-1) of a turn clockwise from 12 o'clock: folded to the nearest quarter turn, so the series
/// to the ninth power only sees up to an eighth of a turn, where it is within float precision.
static void turn_sin_cos(float turns, float *sin_out, float *cos_out) {
    int quarter = (int)(turns * 4.0f + 0.5f);
    float a = (turns - (float)quarter / 4.0f) * 6.2831853f, a2 = a * a;
    float s = a * (1.0f - a2 / 6.0f * (1.0f - a2 / 20.0f * (1.0f - a2 / 42.0f * (1.0f - a2 / 72.0f))));
    float c = 1.0f - a2 / 2.0f * (1.0f - a2 / 12.0f * (1.0f - a2 / 30.0f * (1.0f - a2 / 56.0f)));
    switch (quarter & 3) {
    case 0: *sin_out = s; *cos_out = c; break;
    case 1: *sin_out = c; *cos_out = -s; break;
    case 2: *sin_out = -s; *cos_out = -c; break;
    default: *sin_out = -c; *cos_out = s; break;
    }
}

static int in_frame(int x, int y) { return x >= 0 && x < DFW_SIZE && y >= 0 && y < DFW_SIZE; }

void dfw_band_pixels(const dfw_unit *unit, dfw_put put, void *ctx) {
    if (!unit->drawn || unit->deck.number == 0 || dfw_stale(unit) || !unit->time_heard || unit->track_length == 0)
        return;
    uint16_t elapsed = unit->elapsed < unit->track_length ? unit->elapsed : unit->track_length;
    float turns = (float)elapsed / (float)unit->track_length;
    dfw_pixel fill = unit->time_look == DFW_TIME_RED ? WARNING_RED : unit->time_look == DFW_TIME_WHITE ? WARNING_WHITE
        : (dfw_pixel)unit->deck.r << 16 | (dfw_pixel)unit->deck.g << 8 | unit->deck.b;
    float sn, cs;
    turn_sin_cos(turns, &sn, &cs);
    // Into the fill across the end's ray: counterclockwise of it. The fill is the band on the clockwise side of the
    // 12 o'clock ray and before the end's: up to half a turn both half-planes (their covers' sum less one), past it
    // either (their sum). Swift draws no fill at 0 and the whole band, with no edge, at 1.
    const float end_nx = -cs, end_ny = -sn;
    for (int y = (int)CENTER - REACH; y <= (int)CENTER + REACH; y++) {
        float dy = (float)y + 0.5f - CENTER;
        for (int x = (int)CENTER - REACH; x <= (int)CENTER + REACH; x++) {
            float dx = (float)x + 0.5f - CENTER;
            float d2 = dx * dx + dy * dy;
            if (d2 > (BAND_OUTER + 1.0f) * (BAND_OUTER + 1.0f) || d2 < (BAND_INNER - 1.0f) * (BAND_INNER - 1.0f)) continue;
            float r = root(d2), nx = dx / r, ny = dy / r;
            float band = edge_cover(BAND_OUTER - r, nx, ny) + edge_cover(r - BAND_INNER, nx, ny) - 1.0f;
            if (band <= 0.0f) continue;
            dfw_pixel color = blend(in_frame(x, y) ? GROUND : PANEL, BAND_TRACK, band);
            if (turns > 0.0f) {
                float cover = 1.0f;
                if (turns < 1.0f) {
                    float start = edge_cover(dx, 1.0f, 0.0f), end = edge_cover(dx * end_nx + dy * end_ny, end_nx, end_ny);
                    cover = clamp01(turns <= 0.5f ? start + end - 1.0f : start + end);
                }
                color = blend(color, fill, band * cover);
            }
            put(ctx, x, y, color);
        }
    }
}

static uint16_t rgb565(dfw_pixel p) {
    return (uint16_t)(((p >> 8) & 0xF800u) | ((p >> 5) & 0x07E0u) | ((p >> 3) & 0x001Fu));
}

/// Frame (x, y) to its place in the layer, turned 180° as the frame is presented; -1 off the layer.
static int layer_index(int x, int y) {
    int px = DFW_FRAME_X + DFW_SIZE - 1 - x, py = DFW_FRAME_Y + DFW_SIZE - 1 - y;
    if (px < 0 || px >= DFW_LAYER_W || py < 0 || py >= DFW_LAYER_H) return -1;
    return py * DFW_LAYER_W + px;
}

static void layer_put(void *ctx, int x, int y, dfw_pixel color) {
    if (in_frame(x, y)) return;
    int i = layer_index(x, y);
    if (i >= 0) ((uint16_t *)ctx)[i] = rgb565(color);
}

/// The band's annulus as far as any of its pixels reach (r 102-108, with half a pixel to spare).
#define CLEAR_INNER 101.5f
#define CLEAR_OUTER 108.5f

void dfw_draw_band(uint16_t *layer, const dfw_unit *unit) {
    for (int y = (int)CENTER - REACH; y <= (int)CENTER + REACH; y++) {
        float dy = (float)y + 0.5f - CENTER;
        for (int x = (int)CENTER - REACH; x <= (int)CENTER + REACH; x++) {
            float dx = (float)x + 0.5f - CENTER, d2 = dx * dx + dy * dy;
            if (in_frame(x, y) || d2 < CLEAR_INNER * CLEAR_INNER || d2 > CLEAR_OUTER * CLEAR_OUTER) continue;
            int i = layer_index(x, y);
            if (i >= 0) layer[i] = 0;
        }
    }
    dfw_band_pixels(unit, layer_put, layer);
}
