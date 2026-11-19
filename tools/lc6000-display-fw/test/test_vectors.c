// The shared message vectors (#456): every message in the file decodes to its fields, every invalid one is ignored.
// The Swift encoder walks the same file in the Kit tests.
#include "harness.h"
#include <string.h>

enum { KIND_CAPABILITY, KIND_CAPABILITY_ANSWER, KIND_BEGIN, KIND_END, KIND_DECK };
typedef struct {
    const char *name;
    int kind, from_unit, version, number;
    int color[3];
    int player;
    size_t length;
    uint8_t bytes[64];
} vector;
typedef struct {
    const char *name;
    int from_unit;
    size_t length;
    uint8_t bytes[64];
} bad_vector;

#include "vectors.h"

#define COUNT(a) (sizeof(a) / sizeof((a)[0]))
#define BEGIN_V1 "F0 00 02 0B 7F 10 20 00 02 01 01 F7"
#define DECK_3_GREEN_SEQ "F0 00 02 0B 7F 10 20 00 09 03 03 00 00 01 7F 00 00 04 F7"

static dfw_unit unit;
static recording rec;

static void check(int ok, const char *name) {
    CHECK(ok);
    if (!ok) fprintf(stderr, "  in vector: %s\n", name);
}

void every_vector_decodes(void) {
    CHECK(COUNT(valid_vectors) > 0);
    for (size_t i = 0; i < COUNT(valid_vectors); i++) {
        const vector *v = &valid_vectors[i];
        fresh(&unit, &rec);
        switch (v->kind) {
        case KIND_CAPABILITY:
            dfw_message(&unit, v->bytes, v->length);
            dfw_tick(&unit);
            check(rec.sends == 1 && rec.sent[10] == (v->version < 1 ? v->version : 1), v->name);
            break;
        case KIND_CAPABILITY_ANSWER: {
            // Ours to send: asking at that version gets exactly these bytes.
            uint8_t ask[] = { 0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x20, 0x00, 0x02, 0x00, (uint8_t)v->version, 0xF7 };
            dfw_message(&unit, ask, sizeof ask);
            dfw_tick(&unit);
            check(rec.sends == 1 && rec.sent_length == v->length && memcmp(rec.sent, v->bytes, v->length) == 0, v->name);
            break;
        }
        case KIND_BEGIN:
            dfw_message(&unit, v->bytes, v->length);
            dfw_tick(&unit);
            check(unit.drawn, v->name);
            break;
        case KIND_END:
            feed(&unit, BEGIN_V1);
            dfw_message(&unit, v->bytes, v->length);
            dfw_tick(&unit);
            check(!unit.drawn, v->name);
            break;
        case KIND_DECK:
            feed(&unit, BEGIN_V1);
            dfw_message(&unit, v->bytes, v->length);
            dfw_tick(&unit);
            check(rec.presents == 1 && unit.deck.number == v->number && unit.deck.r == v->color[0] &&
                  unit.deck.g == v->color[1] && unit.deck.b == v->color[2] && unit.deck.player == v->player, v->name);
            break;
        default:
            check(0, v->name);
        }
    }
}

void every_invalid_vector_is_ignored(void) {
    CHECK(COUNT(invalid_vectors) > 0);
    for (size_t i = 0; i < COUNT(invalid_vectors); i++) {
        const bad_vector *v = &invalid_vectors[i];
        fresh(&unit, &rec);
        feed(&unit, BEGIN_V1);
        feed(&unit, DECK_3_GREEN_SEQ);
        dfw_tick(&unit);
        dfw_deck_state before = unit.deck;
        dfw_message(&unit, v->bytes, v->length);
        dfw_tick(&unit);
        check(unit.drawn && rec.presents == 1 && rec.sends == 0 && memcmp(&unit.deck, &before, sizeof before) == 0,
              v->name);
    }
}
