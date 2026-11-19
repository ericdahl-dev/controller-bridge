// The drawing (#457), checked against design B as the Swift renderer draws it: test/ref/*.ppm, made by
// test/ref/make_refs.sh from JogDisplayRenderer, never from this code.
//
// The Swift image also has the title, caption, rule and key/BPM, which this ticket doesn't draw. So only two bands are
// compared with the reference: the ring band and the header band. Everywhere else must be plain ground.
#include "harness.h"
#include "draw.h"
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

/// Two limits per band: no pixel may be off by more than CAP in any channel, and at most BUDGET pixels may be off by
/// more than CLOSE.
///
/// Measured: the ring is within 3 levels everywhere, so it gets 6 and no budget. In the header, CoreGraphics' fill
/// anti-aliasing is not exact pixel area: near 45° on the chip's curve it covers up to about 7% less, which is up to 18
/// levels for a white chip on the ground (244 apart). That touches 8 to 16 pixels per case, all on the chip's edge; the
/// rest of the header, glyphs and badge included, is within 8. So 8 with a budget of 24, and nothing past 24 (9% of
/// full scale) anywhere. A color off by 17 or more (a ring section, the badge ink or outline, the deck color) fails the
/// close limit across hundreds of pixels; a shape off by a pixel or a glyph off by half fails the cap.
#define RING_CLOSE 6
#define RING_BUDGET 0
#define HEADER_CLOSE 8
#define HEADER_BUDGET 24
#define CAP 24

static dfw_pixel frame[DFW_SIZE * DFW_SIZE];

static int channel_diff(dfw_pixel a, dfw_pixel b) {
    int worst = 0;
    for (int shift = 0; shift <= 16; shift += 8) {
        int d = (int)(a >> shift & 0xFF) - (int)(b >> shift & 0xFF);
        if (d < 0) d = -d;
        if (d > worst) worst = d;
    }
    return worst;
}

typedef enum { RING, HEADER } band;

/// Compares one band with the reference: whether it is within its limits. Prints its numbers so they stay honest.
static int band_matches(const ref_case *c, band which) {
    int close = which == RING ? RING_CLOSE : HEADER_CLOSE, budget = which == RING ? RING_BUDGET : HEADER_BUDGET;
    int loose = 0, over_cap = 0, worst = 0, pixels = 0;
    for (int y = 0; y < DFW_SIZE; y++)
        for (int x = 0; x < DFW_SIZE; x++) {
            int ring = in_ring(x, y);
            if (which == RING ? !ring : (ring || !in_header(y))) continue;
            int d = channel_diff(frame[y * DFW_SIZE + x], reference[y * DFW_SIZE + x]);
            pixels++;
            if (d > worst) worst = d;
            if (d > close) loose++;
            if (d > CAP) over_cap++;
        }
    fprintf(stderr, "    %s %s: %d px, worst %d, %d over %d (budget %d)\n", c->file + 9, which == RING ? "ring" : "header",
            pixels, worst, loose, close, budget);
    return over_cap == 0 && loose <= budget;
}

static void draw_case(const ref_case *c) {
    static dfw_unit unit;
    unit.deck = (dfw_deck_state){ c->number, c->r, c->g, c->b, c->player };
    dfw_draw(frame, &unit);
}

static void outside_the_bands_is_plain_ground(void) {
    for (size_t c = 0; c < CASES; c++) {
        draw_case(&cases[c]);
        int stray = 0;
        for (int y = 0; y < DFW_SIZE; y++)
            for (int x = 0; x < DFW_SIZE; x++)
                if (!in_ring(x, y) && !in_header(y) && frame[y * DFW_SIZE + x] != GROUND) stray++;
        CHECK(stray == 0);
    }
}

static void the_ring_matches_the_reference(void) {
    for (size_t c = 0; c < CASES; c++) {
        CHECK(load_reference(cases[c].file));
        draw_case(&cases[c]);
        CHECK(band_matches(&cases[c], RING));
    }
}

static void the_header_matches_the_reference(uint8_t player) {
    for (size_t c = 0; c < CASES; c++) {
        if (cases[c].player != player) continue;
        CHECK(load_reference(cases[c].file));
        draw_case(&cases[c]);
        CHECK(band_matches(&cases[c], HEADER));
    }
}

static void an_empty_deck_draws_its_chip_alone(void) { the_header_matches_the_reference(0); }
static void another_player_draws_its_chip_alone(void) { the_header_matches_the_reference(5); }

static void a_track_draws_the_trk_badge(void) { the_header_matches_the_reference(1); }
static void an_osc_clip_draws_the_osc_badge(void) { the_header_matches_the_reference(2); }
static void a_midi_clip_draws_the_midi_badge(void) { the_header_matches_the_reference(3); }
static void a_sequencer_draws_the_seq_badge(void) { the_header_matches_the_reference(4); }

static void every_pixel_is_written_whatever_the_deck(void) {
    static const dfw_deck_state decks[] = { { 0, 1, 2, 3, 0 }, { 255, 9, 9, 9, 255 }, { 5, 0, 0, 0, 6 }, { 2, 255, 0, 0, 1 } };
    for (size_t d = 0; d < sizeof decks / sizeof decks[0]; d++) {
        for (size_t i = 0; i < DFW_SIZE * DFW_SIZE; i++) frame[i] = 0xDEADBEEFu;
        static dfw_unit unit;
        unit.deck = decks[d];
        dfw_draw(frame, &unit);
        int unwritten = 0;
        for (size_t i = 0; i < DFW_SIZE * DFW_SIZE; i++) unwritten += (frame[i] & 0xFF000000u) != 0;
        CHECK(unwritten == 0);
    }
}

/// The whole path (#457): begin then a deck message, and the tick presents design B for that deck.
static dfw_unit unit;
static recording rec;

static void begin_then_deck_presents_the_reference(void) {
    fresh(&unit, &rec);
    feed(&unit, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&unit, "F0 00 02 0B 7F 10 20 00 09 03 02 01 7F 00 00 00 00 01 F7");   // deck 2, red, track
    dfw_tick(&unit, 0);
    CHECK(rec.presents == 1);
    const ref_case *c = &cases[0];
    CHECK(load_reference(c->file));
    memcpy(frame, rec.last, sizeof frame);
    CHECK(band_matches(c, RING));
    CHECK(band_matches(c, HEADER));
}

/// The waiting look (#464), compared over the whole frame: our logo is all of it. The limits are the header's: the
/// logo is curves and a turned capsule, anti-aliased like the chip.
#define STALE_REF "test/ref/stale.ppm"
#define STALE_BUDGET 64

static int stale_matches(void) {
    int loose = 0, over_cap = 0, worst = 0;
    for (int i = 0; i < DFW_SIZE * DFW_SIZE; i++) {
        int d = channel_diff(frame[i], reference[i]);
        if (d > worst) worst = d;
        if (d > HEADER_CLOSE) loose++;
        if (d > CAP) over_cap++;
    }
    fprintf(stderr, "    stale: worst %d, %d over %d (budget %d), %d over %d\n", worst, loose, HEADER_CLOSE, STALE_BUDGET,
            over_cap, CAP);
    return over_cap == 0 && loose <= STALE_BUDGET;
}

static void stale_draws_the_logo(void) {
    static dfw_unit stale_unit;
    stale_unit.deck = (dfw_deck_state){ 2, 255, 0, 0, 1 };
    stale_unit.flags = 0x21;   // loaded, feedback stale
    CHECK(load_reference(STALE_REF));
    dfw_draw(frame, &stale_unit);
    CHECK(stale_matches());
}

static void three_silent_seconds_present_the_logo(void) {
    fresh(&unit, &rec);
    feed(&unit, "F0 00 02 0B 7F 10 20 00 02 01 01 F7");
    feed(&unit, "F0 00 02 0B 7F 10 20 00 09 03 02 01 7F 00 00 00 00 01 F7");
    dfw_tick(&unit, 0);
    dfw_tick(&unit, 3000);
    CHECK(rec.presents == 2);
    CHECK(load_reference(STALE_REF));
    memcpy(frame, rec.last, sizeof frame);
    CHECK(stale_matches());
}

const test_case draw_tests[] = {
    { "outside the bands is plain ground", outside_the_bands_is_plain_ground },
    { "the ring matches the reference", the_ring_matches_the_reference },
    { "an empty deck draws its chip alone", an_empty_deck_draws_its_chip_alone },
    { "another player draws its chip alone", another_player_draws_its_chip_alone },
    { "a track draws the TRK badge", a_track_draws_the_trk_badge },
    { "an OSC clip draws the OSC badge", an_osc_clip_draws_the_osc_badge },
    { "a MIDI clip draws the MIDI badge", a_midi_clip_draws_the_midi_badge },
    { "a sequencer draws the SEQ badge", a_sequencer_draws_the_seq_badge },
    { "every pixel is written whatever the deck", every_pixel_is_written_whatever_the_deck },
    { "every reference has the ring and header to compare", every_reference_has_the_ring_and_header_to_compare },
    { "begin then deck presents the reference", begin_then_deck_presents_the_reference },
    { "stale draws the logo", stale_draws_the_logo },
    { "three silent seconds present the logo", three_silent_seconds_present_the_logo },
    { 0, 0 },
};
