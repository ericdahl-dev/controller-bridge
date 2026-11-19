// The sequence rules as data (#569): every case in vectors/messages.json's "sequences", walked by the chip's own
// dfw.c. The Swift decoder walks the same cases (DrawnDisplaySequenceTests).
#include "harness.h"
#include <string.h>

typedef struct { int at_ms; const char *send; } seq_step;
enum { E_DRAWN, E_DECK, E_FLAGS, E_STALE, E_BEAT, E_NEEDLE, E_TEMPO, E_PHASE, E_TIME, E_TEXT_HEARD, E_LOOK };
typedef struct {
    const char *name;
    size_t step_count;
    seq_step steps[16];
    int mask;
    int drawn, deck, flags, stale, beat, needle, tempo, phase, elapsed, length, text_heard, look;
} seq_case;

#include "sequences.h"

static dfw_unit unit;
static recording rec;

static void expect(const seq_case *c, int which, int ok, const char *what) {
    if (!(c->mask & (1 << which))) return;
    CHECK(ok);
    if (!ok) fprintf(stderr, "  in case: %s (%s)\n", c->name, what);
}

void every_sequence_case_holds(void) {
    size_t count = sizeof seq_cases / sizeof seq_cases[0];
    CHECK(count > 0);
    for (size_t i = 0; i < count; i++) {
        const seq_case *c = &seq_cases[i];
        fresh(&unit, &rec);
        for (size_t s = 0; s < c->step_count; s++) {
            if (c->steps[s].send) feed(&unit, c->steps[s].send);
            dfw_tick(&unit, (uint32_t)c->steps[s].at_ms);
        }
        expect(c, E_DRAWN, unit.drawn == c->drawn, "drawn");
        expect(c, E_DECK, unit.deck.number == c->deck, "deck");
        expect(c, E_FLAGS, unit.flags == c->flags, "flags");
        expect(c, E_STALE, (dfw_stale(&unit) != 0) == c->stale, "stale");
        expect(c, E_BEAT, unit.beat == c->beat, "beat");
        expect(c, E_NEEDLE, unit.needle_heard ? unit.needle == c->needle : c->needle == -1, "needle");
        expect(c, E_TEMPO, unit.tempo == c->tempo, "tempo");
        expect(c, E_PHASE, unit.phase == c->phase, "phase");
        expect(c, E_TIME, unit.time_heard ? unit.elapsed == c->elapsed && unit.track_length == c->length : c->elapsed == -1,
               "time");
        expect(c, E_TEXT_HEARD, unit.text_heard == c->text_heard, "text_heard");
        expect(c, E_LOOK, unit.time_look == c->look, "look");
    }
}
