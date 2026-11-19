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
/// off. Measured: worst 8, on 6 or 7 pixels per beat. A 1 px shift (hundreds of levels) or a wrong green fails.
#define LIT_CLOSE 10

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

/// The ring band of `frame` against `reference`: whether no pixel is more than `close` off. Prints its worst.
static int ring_matches(const char *name, int close) {
    int worst = 0, loose = 0;
    for (int y = 0; y < DFW_SIZE; y++)
        for (int x = 0; x < DFW_SIZE; x++) {
            if (!in_ring(x, y)) continue;
            int d = channel_diff(frame[y * DFW_SIZE + x], reference[y * DFW_SIZE + x]);
            if (d > worst) worst = d;
            if (d > close) loose++;
        }
    fprintf(stderr, "    %s ring: worst %d, %d over %d\n", name, worst, loose, close);
    return loose == 0;
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
        CHECK(ring_matches(files[beat] + 9, LIT_CLOSE));
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
    CHECK(ring_matches("deck4-blue-empty.ppm (beat 0)", RING_CLOSE));
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

const test_case draw_live_tests[] = {
    { "each beat lights its section", each_beat_lights_its_section },
    { "each lit reference differs from the unlit one", each_lit_reference_differs_from_the_unlit_one },
    { "no master clock lights no section", no_master_clock_lights_no_section },
    { "stale lights no section", stale_lights_no_section },
    { 0, 0 },
};
