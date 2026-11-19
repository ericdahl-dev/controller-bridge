// The drawing (#457), checked against design B as the Swift renderer draws it: test/ref/*.ppm, made by
// test/ref/make_refs.sh from JogDisplayRenderer, never from this code.
//
// The Swift image also has the title, caption, rule and key/BPM, which this ticket doesn't draw. So only two bands are
// compared with the reference: the ring band and the header band. Everywhere else must be plain ground.
#include "harness.h"
#include <string.h>

#define GROUND 0x0B0B0Bu
/// The header band (chip and badge, 24-50) with room for anti-aliasing; the title's glyphs start below 66.
#define HEADER_TOP 20
#define HEADER_BOTTOM 55
/// The ring band, 85-95 around (99, 99), with room for anti-aliasing; text stays inside 79.
#define RING_IN 83.5f
#define RING_OUT 96.5f

typedef struct {
    const char *file;
    uint8_t number, r, g, b, player;
} ref_case;

static const ref_case cases[] = {
    { "test/ref/deck2-red-track.ppm", 2, 255, 0, 0, 1 },
    { "test/ref/deck4-blue-empty.ppm", 4, 0, 128, 255, 0 },
    { "test/ref/deck1-white-midi.ppm", 1, 255, 255, 255, 3 },
    { "test/ref/deck3-green-other.ppm", 3, 0, 200, 80, 5 },
    { "test/ref/deck1-orange-osc.ppm", 1, 255, 128, 0, 2 },
    { "test/ref/deck3-purple-seq.ppm", 3, 180, 0, 255, 4 },
};
#define CASES (sizeof cases / sizeof cases[0])

static dfw_pixel reference[DFW_SIZE * DFW_SIZE];

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

static int in_header(int y) { return y >= HEADER_TOP && y <= HEADER_BOTTOM; }

static int in_ring(int x, int y) {
    float dx = (float)x + 0.5f - 99.0f, dy = (float)y + 0.5f - 99.0f, d2 = dx * dx + dy * dy;
    return d2 >= RING_IN * RING_IN && d2 <= RING_OUT * RING_OUT;
}

static void every_reference_has_the_ring_and_header_to_compare(void) {
    for (size_t c = 0; c < CASES; c++) {
        CHECK(load_reference(cases[c].file));
        CHECK(reference[0] == GROUND);
        int ring = 0, header = 0;
        for (int y = 0; y < DFW_SIZE; y++)
            for (int x = 0; x < DFW_SIZE; x++) {
                if (reference[y * DFW_SIZE + x] == GROUND) continue;
                if (in_ring(x, y)) ring++;
                else if (in_header(y)) header++;
            }
        // Not vacuous: both bands hold drawing (the ring's band alone is thousands of pixels; the chip hundreds).
        CHECK(ring > 4000);
        CHECK(header > 300);
    }
}

const test_case draw_tests[] = {
    { "every reference has the ring and header to compare", every_reference_has_the_ring_and_header_to_compare },
    { 0, 0 },
};
