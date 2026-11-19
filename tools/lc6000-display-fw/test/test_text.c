// The text measure (#458): a line's width as the renderer lays it out, from advances, ligatures, kerning and tracking
// in font units, checked against CoreText's own widths (test/ref/text_widths.h, made by gen/text_font_gen.swift).
#include "harness.h"
#include "text.h"
#include "ref/text_widths.h"
#include <math.h>
#include <string.h>

static const dfw_text_face *face_named(const char *name) {
    if (strcmp(name, "title26") == 0) return dfw_title26;
    if (strcmp(name, "title20") == 0) return dfw_title20;
    if (strcmp(name, "caption16") == 0) return dfw_caption16;
    if (strcmp(name, "mono18") == 0) return dfw_mono18;
    return NULL;
}

static void every_width_matches_coretext(void) {
    size_t count = sizeof text_width_cases / sizeof text_width_cases[0];
    CHECK(count > 0);
    for (size_t i = 0; i < count; i++) {
        const text_width_case *c = &text_width_cases[i];
        const dfw_text_face *face = face_named(c->face);
        CHECK(face != NULL);
        if (!face) continue;
        const uint8_t *codes = (const uint8_t *)c->codes;
        float width = dfw_text_width(face, codes, strlen(c->codes), c->tracked);
        if (fabs(width - c->width) > 0.01) {
            harness_failures++;
            fprintf(stderr, "  %s%s: %f, CoreText %f (", c->face, c->tracked ? " tracked" : "", width, c->width);
            for (const char *p = c->codes; *p; p++) fprintf(stderr, "%02X", (uint8_t)*p);
            fprintf(stderr, ")\n");
        }
    }
}

const test_case text_tests[] = {
    { "every width matches CoreText", every_width_matches_coretext },
    { 0, 0 },
};
