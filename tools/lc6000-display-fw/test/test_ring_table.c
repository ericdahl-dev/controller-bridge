// The beat ring drawn from its table (#558) is the geometry it replaced, pixel for pixel: unlit, all dark (the waiting
// look) and each beat lit, against src/ring_geometry.h (draw.c's ring() and draw_live.c's lit_section(), verbatim).
#include "harness.h"
#include "draw.h"
#include "ring_geometry.h"
#include <string.h>

#define N (DFW_SIZE * DFW_SIZE)
static dfw_pixel want[N], frame[N];
static uint8_t touched[N];

/// dfw_draw's frame against the geometry's on every pixel the ring (and the lit section) draws.
static int ring_matches(const dfw_unit *unit, int all_dark, int beat) {
    for (int i = 0; i < N; i++) want[i] = GROUND;
    memset(touched, 0, sizeof touched);
    ring_geometry(want, all_dark, touched);
    if (beat) lit_geometry(want, beat, touched);
    dfw_draw(frame, unit);
    int off = 0, count = 0;
    for (int i = 0; i < N; i++)
        if (touched[i]) {
            count++;
            off += frame[i] != want[i];
        }
    return count > 5000 && off == 0;
}

static void the_ring_from_its_table_is_the_geometry(void) {
    static dfw_unit unit;
    memset(&unit, 0, sizeof unit);
    unit.drawn = 1;
    unit.deck = (dfw_deck_state){ 4, 0, 128, 255, 0 };
    unit.phase = DFW_PHASE_UNKNOWN;
    for (uint8_t beat = 0; beat <= 4; beat++) {
        unit.beat = beat;
        CHECK(ring_matches(&unit, 0, beat));
    }
    unit.flags = 0x20;   // feedback stale: all dark, no beat
    unit.beat = 3;
    CHECK(ring_matches(&unit, 1, 0));
}

const test_case ring_table_tests[] = {
    { "the ring from its table is the geometry", the_ring_from_its_table_is_the_geometry },
    { 0, 0 },
};
