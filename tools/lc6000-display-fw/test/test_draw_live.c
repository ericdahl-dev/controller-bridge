// The live elements (#459): the lit master beat and the marker, checked against JogDisplayRenderer's simulator image:
// test/ref/*-beat*.ppm and *-needle*.ppm, made by test/ref/make_refs.sh with the live-reference tool, never from this
// code. Every case is deck 4, blue, empty: its header is the chip alone, and nothing else is drawn near the ring.
#include "harness.h"
#include "draw.h"
#include <string.h>

#define UNLIT "test/ref/deck4-blue-empty.ppm"
/// The ring band, 85-95 around (99, 99), with room for anti-aliasing, as test_draw.c compares it.
#define RING_IN 83.5f
#define RING_OUT 96.5f
/// As test_draw.c: the unlit ring within 6 levels everywhere.
#define RING_CLOSE 6
/// The lit section is the live green on the ground, 244 levels apart in green, three times the unlit sections' 79. The
/// renderers' anti-aliasing differs by the same fraction of that (about 4%), so a few of its edge pixels are up to 8
/// off. Measured: worst 8, with 6 or 7 pixels over 6 per beat. So 6 with a budget of 10, and nothing past 10: a green
/// off by 7 or more fails across the section, and a 1 px shift (hundreds of levels) fails the cap.
#define LIT_CLOSE 6
#define LIT_BUDGET 10
#define LIT_CAP 10

static dfw_pixel reference[DFW_SIZE * DFW_SIZE];
static dfw_pixel frame[DFW_SIZE * DFW_SIZE];

/// Reads a binary PPM (P6, 198×198, maxval 255) into `reference`. A missing or short file fails, never skips.
static int load_reference(const char *file) {
    FILE *f = fopen(file, "rb");
    if (!f) { fprintf(stderr, "can't open %s\n", file); return 0; }
    int w = 0, h = 0, max = 0;
    int ok = fscanf(f, "P6 %d %d %d", &w, &h, &max) == 3 && w == DFW_SIZE && h == DFW_SIZE && max == 255
        && fgetc(f) == '\n';
    static uint8_t rgb[DFW_SIZE * DFW_SIZE * 3];
    ok = ok && fread(rgb, 1, sizeof rgb, f) == sizeof rgb;
    fclose(f);
    if (!ok) { fprintf(stderr, "%s is not a %dx%d P6 PPM\n", file, DFW_SIZE, DFW_SIZE); return 0; }
    for (size_t i = 0; i < DFW_SIZE * DFW_SIZE; i++)
        reference[i] = (dfw_pixel)rgb[i * 3] << 16 | (dfw_pixel)rgb[i * 3 + 1] << 8 | rgb[i * 3 + 2];
    return 1;
}

static float radius2(int x, int y) {
    float dx = (float)x + 0.5f - 99.0f, dy = (float)y + 0.5f - 99.0f;
    return dx * dx + dy * dy;
}

static int in_ring(int x, int y) {
    float d2 = radius2(x, y);
    return d2 >= RING_IN * RING_IN && d2 <= RING_OUT * RING_OUT;
}

static int channel_diff(dfw_pixel a, dfw_pixel b) {
    int worst = 0;
    for (int shift = 0; shift <= 16; shift += 8) {
        int d = (int)(a >> shift & 0xFF) - (int)(b >> shift & 0xFF);
        if (d < 0) d = -d;
        if (d > worst) worst = d;
    }
    return worst;
}

/// The ring band of `frame` against `reference`: at most `budget` pixels more than `close` off, and none more than
/// `cap`. Prints its numbers.
static int ring_matches(const char *name, int close, int budget, int cap) {
    int worst = 0, loose = 0, over = 0;
    for (int y = 0; y < DFW_SIZE; y++)
        for (int x = 0; x < DFW_SIZE; x++) {
            if (!in_ring(x, y)) continue;
            int d = channel_diff(frame[y * DFW_SIZE + x], reference[y * DFW_SIZE + x]);
            if (d > worst) worst = d;
            if (d > close) loose++;
            if (d > cap) over++;
        }
    fprintf(stderr, "    %s ring: worst %d, %d over %d (budget %d)\n", name, worst, loose, close, budget);
    return over == 0 && loose <= budget;
}

static dfw_unit unit;

/// Deck 4, blue, empty, drawn with this beat and the rest of the unit as the test left it.
static void draw_beat(uint8_t beat) {
    unit.deck = (dfw_deck_state){ 4, 0, 128, 255, 0 };
    unit.beat = beat;
    dfw_draw(frame, &unit);
}

static void each_beat_lights_its_section(void) {
    static const char *const files[] = { 0, "test/ref/deck4-blue-empty-beat1.ppm", "test/ref/deck4-blue-empty-beat2.ppm",
                                         "test/ref/deck4-blue-empty-beat3.ppm", "test/ref/deck4-blue-empty-beat4.ppm" };
    memset(&unit, 0, sizeof unit);
    for (uint8_t beat = 1; beat <= 4; beat++) {
        CHECK(load_reference(files[beat]));
        draw_beat(beat);
        CHECK(ring_matches(files[beat] + 9, LIT_CLOSE, LIT_BUDGET, LIT_CAP));
    }
}

/// Not vacuous: each lit reference differs from the unlit one, in its own section only.
static void each_lit_reference_differs_from_the_unlit_one(void) {
    static dfw_pixel unlit[DFW_SIZE * DFW_SIZE];
    CHECK(load_reference(UNLIT));
    memcpy(unlit, reference, sizeof unlit);
    static const char *const files[] = { "test/ref/deck4-blue-empty-beat1.ppm", "test/ref/deck4-blue-empty-beat2.ppm",
                                         "test/ref/deck4-blue-empty-beat3.ppm", "test/ref/deck4-blue-empty-beat4.ppm" };
    for (int b = 0; b < 4; b++) {
        CHECK(load_reference(files[b]));
        int changed = 0;
        for (int i = 0; i < DFW_SIZE * DFW_SIZE; i++) changed += reference[i] != unlit[i];
        CHECK(changed > 1000);
    }
}

static void no_master_clock_lights_no_section(void) {
    memset(&unit, 0, sizeof unit);
    CHECK(load_reference(UNLIT));
    draw_beat(0);
    CHECK(ring_matches("deck4-blue-empty.ppm (beat 0)", RING_CLOSE, 0, RING_CLOSE));
}

/// The waiting look is agent3's; whatever it is, the beat changes none of it.
static void stale_lights_no_section(void) {
    static dfw_pixel without[DFW_SIZE * DFW_SIZE];
    memset(&unit, 0, sizeof unit);
    unit.flags = 0x20;
    draw_beat(0);
    memcpy(without, frame, sizeof without);
    for (uint8_t beat = 1; beat <= 4; beat++) {
        draw_beat(beat);
        CHECK(memcmp(frame, without, sizeof frame) == 0);
    }
    memset(&unit, 0, sizeof unit);
    unit.silent = 1;
    draw_beat(0);
    memcpy(without, frame, sizeof without);
    draw_beat(3);
    CHECK(memcmp(frame, without, sizeof frame) == 0);
}

/// The marker reaches in to radius 78 (its tip at 79, less its keyline) and out past the frame's edge. The chip, the
/// only other thing drawn for this deck, stays inside 76. So everything from 77 out is compared.
#define MARKER_IN 77.0f
/// Measured: with the fill's exact area in each edge pixel, the marker is within 3 levels everywhere, at the five
/// references and at 19 more angles swept round the turn. So 6 and no budget, as the unlit ring. Turning the marker
/// half a degree puts dozens of pixels hundreds of levels off.
#define MARKER_CLOSE 6
#define MARKER_BUDGET 0
#define MARKER_CAP 6

/// Everything from MARKER_IN out against `reference`, within limits as test_draw.c's: at most `budget` pixels more than
/// `close` off, and none more than `cap`. Prints its numbers.
static int band_from_matches(const char *name, int close, int budget, int cap) {
    int worst = 0, loose = 0, over = 0;
    for (int y = 0; y < DFW_SIZE; y++)
        for (int x = 0; x < DFW_SIZE; x++) {
            if (radius2(x, y) < MARKER_IN * MARKER_IN) continue;
            int d = channel_diff(frame[y * DFW_SIZE + x], reference[y * DFW_SIZE + x]);
            if (d > worst) worst = d;
            if (d > close) loose++;
            if (d > cap) over++;
        }
    fprintf(stderr, "    %s from %.0f out: worst %d, %d over %d (budget %d)\n", name, (double)MARKER_IN, worst, loose,
            close, budget);
    return over == 0 && loose <= budget;
}

static int marker_band_matches(const char *name) {
    return band_from_matches(name, MARKER_CLOSE, MARKER_BUDGET, MARKER_CAP);
}

typedef struct { const char *file; uint16_t needle; } needle_case;
static const needle_case needles[] = {
    { "test/ref/deck4-blue-empty-needle0.ppm", 0 },
    { "test/ref/deck4-blue-empty-needle4096.ppm", 4096 },
    { "test/ref/deck4-blue-empty-needle8192.ppm", 8192 },
    { "test/ref/deck4-blue-empty-needle12288.ppm", 12288 },
    // Off the quarter turns, so the angle's sine and cosine are really computed.
    { "test/ref/deck4-blue-empty-needle1500.ppm", 1500 },
};
#define NEEDLES (sizeof needles / sizeof needles[0])

static dfw_unit live;
static recording rec;

/// Begin, deck 4 blue empty, then a needle message at `angle`, then a tick.
static void begin_with_needle(uint16_t angle) {
    fresh(&live, &rec);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&live, "F0 00 02 0B 7F 10 20 00 09 03 04 00 00 01 00 01 7F 00 F7");   // deck 4, 0/128/255, empty
    char needle[64];
    snprintf(needle, sizeof needle, "F0 00 02 0B 7F 10 20 00 03 09 %02X %02X F7", angle >> 7, angle & 0x7F);
    feed(&live, needle);
    dfw_tick(&live, 0);
}

static void the_needle_is_drawn_as_the_marker(void) {
    for (size_t n = 0; n < NEEDLES; n++) {
        CHECK(load_reference(needles[n].file));
        begin_with_needle(needles[n].needle);
        CHECK(rec.presents == 1);
        memcpy(frame, rec.last, sizeof frame);
        CHECK(marker_band_matches(needles[n].file + 9));
    }
}

/// The marker drawn over the lit section it sits in: beat 3, needle 11000 (folded back from the last quarter turn).
static void the_marker_is_drawn_over_the_lit_section(void) {
    CHECK(load_reference("test/ref/deck4-blue-empty-beat3-needle11000.ppm"));
    begin_with_needle(11000);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 08 03 F7");   // beat 3
    dfw_tick(&live, 10);
    CHECK(rec.presents == 2);
    memcpy(frame, rec.last, sizeof frame);
    CHECK(band_from_matches("deck4-blue-empty-beat3-needle11000.ppm", LIT_CLOSE, LIT_BUDGET, LIT_CAP));
}

/// Not vacuous: each marker reference differs from the unlit one from MARKER_IN out.
static void each_marker_reference_differs_from_the_unlit_one(void) {
    static dfw_pixel unlit[DFW_SIZE * DFW_SIZE];
    CHECK(load_reference(UNLIT));
    memcpy(unlit, reference, sizeof unlit);
    for (size_t n = 0; n < NEEDLES; n++) {
        CHECK(load_reference(needles[n].file));
        int changed = 0;
        for (int y = 0; y < DFW_SIZE; y++)
            for (int x = 0; x < DFW_SIZE; x++)
                changed += radius2(x, y) >= MARKER_IN * MARKER_IN && reference[y * DFW_SIZE + x] != unlit[y * DFW_SIZE + x];
        CHECK(changed > 150);
    }
}

/// Until a needle message comes there is no marker: the host's full state carries one, and nothing is made up.
static void no_needle_message_draws_no_marker(void) {
    fresh(&live, &rec);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&live, "F0 00 02 0B 7F 10 20 00 09 03 04 00 00 01 00 01 7F 00 F7");
    dfw_tick(&live, 0);
    CHECK(load_reference(UNLIT));
    memcpy(frame, rec.last, sizeof frame);
    CHECK(marker_band_matches("deck4-blue-empty.ppm (no needle)"));
}

static void a_needle_message_changes_the_frame(void) {
    static dfw_pixel before[DFW_SIZE * DFW_SIZE];
    begin_with_needle(0);
    memcpy(before, rec.last, sizeof before);
    feed(&live, "F0 00 02 0B 7F 10 20 00 03 09 08 00 F7");   // 1024, an eighth of a turn
    dfw_tick(&live, 10);
    CHECK(rec.presents == 2);
    CHECK(memcmp(rec.last, before, sizeof before) != 0);
}

/// The first needle message draws the marker even at 0, the angle a fresh unit holds.
static void the_first_needle_at_12_oclock_presents(void) {
    fresh(&live, &rec);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&live, "F0 00 02 0B 7F 10 20 00 09 03 04 00 00 01 00 01 7F 00 F7");
    dfw_tick(&live, 0);
    CHECK(rec.presents == 1);
    feed(&live, "F0 00 02 0B 7F 10 20 00 03 09 00 00 F7");
    dfw_tick(&live, 10);
    CHECK(rec.presents == 2);
}

static void the_same_angle_does_not_present_again(void) {
    begin_with_needle(4096);
    CHECK(rec.presents == 1);
    feed(&live, "F0 00 02 0B 7F 10 20 00 03 09 20 00 F7");   // 4096 again
    dfw_tick(&live, 10);
    CHECK(rec.presents == 1);
}

/// End forgets the needle: after a new begin there is no marker until a needle message comes.
static void end_forgets_the_needle(void) {
    begin_with_needle(4096);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 02 01 F7");
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&live, "F0 00 02 0B 7F 10 20 00 09 03 04 00 00 01 00 01 7F 00 F7");
    dfw_tick(&live, 10);
    CHECK(load_reference(UNLIT));
    memcpy(frame, rec.last, sizeof frame);
    CHECK(marker_band_matches("deck4-blue-empty.ppm (after end)"));
}

/// The waiting look is agent3's; whatever it is, the needle changes none of it.
static void stale_draws_no_marker(void) {
    static dfw_pixel without[DFW_SIZE * DFW_SIZE];
    memset(&unit, 0, sizeof unit);
    unit.flags = 0x20;
    draw_beat(0);
    memcpy(without, frame, sizeof without);
    unit.needle_heard = 1;
    unit.needle = 4096;
    draw_beat(0);
    CHECK(memcmp(frame, without, sizeof frame) == 0);
}

/// Play state shows only through the needle, as the unit's own does: it moves while playing and holds while paused.
/// Nothing is drawn for it: every combination of loaded, playing and play pending is the same frame.
static void the_play_flags_change_no_pixels(void) {
    static dfw_pixel first[DFW_SIZE * DFW_SIZE];
    begin_with_needle(1500);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 08 02 F7");   // beat 2
    for (uint8_t flags = 0; flags <= 7; flags++) {
        char state[64];
        snprintf(state, sizeof state, "F0 00 02 0B 7F 10 20 00 02 07 %02X F7", flags);
        feed(&live, state);
        dfw_tick(&live, 10u + flags);
        CHECK(rec.presents == 2 + flags);
        if (flags == 0) memcpy(first, rec.last, sizeof first);
        else CHECK(memcmp(rec.last, first, sizeof first) == 0);
    }
}

/// The level meter (#461): an arc 80-83 inside the ring on the left, Swift's drawMeter. Compared, as the marker is,
/// from MARKER_IN out: the meter, the ring and nothing else of this deck's. Its edges against the dark track are within
/// 3. Against the bright fill, the band's two circles land about 0.03 px further in in CoreGraphics than their exact
/// areas put them, as the lit section's do, and the band is all edge: measured, worst 13 with 46 pixels over 6, all on
/// the circles, none on the radial edges or the tick; at clip, the whole arc bright, 89. So 6 with a budget a little
/// over each case's count, and nothing past 16 in any: a quarter pixel off is 60 levels on every edge pixel of the fill.
#define METER_CLOSE 6
#define METER_CAP 16

typedef struct { const char *file; uint8_t level, peak; int budget; } meter_case;
static const meter_case meters[] = {
    { "test/ref/deck4-blue-empty-meter0-0.ppm", 0, 0, 0 },
    { "test/ref/deck4-blue-empty-meter64-90.ppm", 64, 90, 50 },
    // High: green, then yellow above 0.75, the white tick over the yellow.
    { "test/ref/deck4-blue-empty-meter110-120.ppm", 110, 120, 30 },
    // Clip: the whole arc red, and the tick red at the top.
    { "test/ref/deck4-blue-empty-meter127-127.ppm", 127, 127, 95 },
};
#define METERS (sizeof meters / sizeof meters[0])

/// Begin, deck 4 blue empty, then a meter message, then a tick.
static void begin_with_meter(uint8_t level, uint8_t peak) {
    fresh(&live, &rec);
    feed(&live, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&live, "F0 00 02 0B 7F 10 20 00 09 03 04 00 00 01 00 01 7F 00 F7");
    char meter[64];
    snprintf(meter, sizeof meter, "F0 00 02 0B 7F 10 20 00 03 0A %02X %02X F7", level, peak);
    feed(&live, meter);
    dfw_tick(&live, 0);
}

static void the_meter_is_drawn(void) {
    for (size_t n = 0; n < METERS; n++) {
        CHECK(load_reference(meters[n].file));
        begin_with_meter(meters[n].level, meters[n].peak);
        CHECK(rec.presents == 1);
        memcpy(frame, rec.last, sizeof frame);
        CHECK(band_from_matches(meters[n].file + 9, METER_CLOSE, meters[n].budget, METER_CAP));
    }
}

/// No reference has a fill past the yellow; the spec's colors are exact where the band covers a pixel whole. Level 110
/// (0.87 of the arc), no peak: mid-band pixels at fractions 0.40 (green), 0.80 (yellow) and 0.96 (the track).
static void the_fill_turns_yellow_past_three_quarters(void) {
    memset(&unit, 0, sizeof unit);
    unit.meter_heard = 1;
    unit.level = 110;
    draw_beat(0);
    CHECK(frame[107 * DFW_SIZE + 17] == 0x00FF48u);
    CHECK(frame[73 * DFW_SIZE + 21] == 0xFFD400u);
    CHECK(frame[61 * DFW_SIZE + 26] == 0x2C2C2Cu);
}

/// No reference has the tick over the fill: level 110 with the peak at 64, a mid-band pixel whole inside the tick
/// (fractions 0.500-0.512 of the tick's 0.487-0.521) is the tick's white, not the fill's green.
static void the_tick_is_drawn_over_the_fill(void) {
    memset(&unit, 0, sizeof unit);
    unit.meter_heard = 1;
    unit.level = 110;
    unit.peak = 64;
    draw_beat(0);
    CHECK(frame[98 * DFW_SIZE + 17] == 0xFFFFFFu);
}

/// No reference has the marker over the meter: at 9 o'clock (needle 12288) over a clipping meter, a pixel whole inside
/// the marker's wedge (half width 1.125 at 82 out) is the marker's white, not the clip red.
static void the_marker_is_drawn_over_the_meter(void) {
    begin_with_needle(12288);
    feed(&live, "F0 00 02 0B 7F 10 20 00 03 0A 7F 7F F7");
    dfw_tick(&live, 10);
    CHECK(rec.presents == 2);
    CHECK(rec.last[99 * DFW_SIZE + 16] == 0xFFFFFFu);
}

/// Not vacuous: each meter reference differs from the unlit one, from MARKER_IN out.
static void each_meter_reference_differs_from_the_unlit_one(void) {
    static dfw_pixel unlit[DFW_SIZE * DFW_SIZE];
    static const char *const files[] = { "test/ref/deck4-blue-empty-meter0-0.ppm",
                                         "test/ref/deck4-blue-empty-meter64-90.ppm",
                                         "test/ref/deck4-blue-empty-meter110-120.ppm",
                                         "test/ref/deck4-blue-empty-meter127-127.ppm" };
    CHECK(load_reference(UNLIT));
    memcpy(unlit, reference, sizeof unlit);
    for (int f = 0; f < 3; f++) {
        CHECK(load_reference(files[f]));
        int changed = 0;
        for (int y = 0; y < DFW_SIZE; y++)
            for (int x = 0; x < DFW_SIZE; x++)
                changed += radius2(x, y) >= MARKER_IN * MARKER_IN && reference[y * DFW_SIZE + x] != unlit[y * DFW_SIZE + x];
        CHECK(changed > 300);
    }
}

/// The waiting look is agent3's; whatever it is, the meter changes none of it.
static void stale_draws_no_meter(void) {
    static dfw_pixel without[DFW_SIZE * DFW_SIZE];
    memset(&unit, 0, sizeof unit);
    unit.flags = 0x20;
    draw_beat(0);
    memcpy(without, frame, sizeof without);
    unit.meter_heard = 1;
    unit.level = 64;
    unit.peak = 90;
    draw_beat(0);
    CHECK(memcmp(frame, without, sizeof frame) == 0);
}

const test_case draw_live_tests[] = {
    { "the meter is drawn", the_meter_is_drawn },
    { "each meter reference differs from the unlit one", each_meter_reference_differs_from_the_unlit_one },
    { "stale draws no meter", stale_draws_no_meter },
    { "the fill turns yellow past three quarters", the_fill_turns_yellow_past_three_quarters },
    { "the tick is drawn over the fill", the_tick_is_drawn_over_the_fill },
    { "the marker is drawn over the meter", the_marker_is_drawn_over_the_meter },
    { "the play flags change no pixels", the_play_flags_change_no_pixels },
    { "the needle is drawn as the marker", the_needle_is_drawn_as_the_marker },
    { "the marker is drawn over the lit section", the_marker_is_drawn_over_the_lit_section },
    { "each marker reference differs from the unlit one", each_marker_reference_differs_from_the_unlit_one },
    { "no needle message draws no marker", no_needle_message_draws_no_marker },
    { "a needle message changes the frame", a_needle_message_changes_the_frame },
    { "the first needle at 12 o'clock presents", the_first_needle_at_12_oclock_presents },
    { "the same angle does not present again", the_same_angle_does_not_present_again },
    { "end forgets the needle", end_forgets_the_needle },
    { "stale draws no marker", stale_draws_no_marker },
    { "each beat lights its section", each_beat_lights_its_section },
    { "each lit reference differs from the unlit one", each_lit_reference_differs_from_the_unlit_one },
    { "no master clock lights no section", no_master_clock_lights_no_section },
    { "stale lights no section", stale_lights_no_section },
    { 0, 0 },
};
