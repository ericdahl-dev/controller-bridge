#include "harness.h"
#include <stdlib.h>
#include <string.h>

int harness_failures = 0;

static void present(void *ctx, const dfw_pixel *frame) {
    recording *rec = ctx;
    rec->presents++;
    memcpy(rec->last, frame, sizeof rec->last);
}

void fresh(dfw_unit *unit, recording *rec) {
    memset(rec, 0, sizeof *rec);
    dfw_port port = { .present = present, .ctx = rec };
    dfw_init(unit, &port);
}

void feed(dfw_unit *unit, const char *hex) {
    uint8_t bytes[1024];
    size_t n = 0;
    const char *p = hex;
    while (*p && n < sizeof bytes) {
        while (*p == ' ') p++;
        if (!*p) break;
        bytes[n++] = (uint8_t)strtoul(p, (char **)&p, 16);
    }
    dfw_message(unit, bytes, n);
}

extern const test_case all_tests[];

int main(void) {
    int run = 0;
    for (const test_case *t = all_tests; t->name; t++, run++) {
        int before = harness_failures;
        t->fn();
        fprintf(stderr, "%s %s\n", harness_failures == before ? "ok  " : "FAIL", t->name);
    }
    fprintf(stderr, "%d tests, %d failed checks\n", run, harness_failures);
    return harness_failures == 0 && run > 0 ? 0 : 1;
}
