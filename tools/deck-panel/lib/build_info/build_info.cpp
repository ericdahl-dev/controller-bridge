#include "build_info.h"

#include <cstdio>

namespace build_info {

namespace {
const char* local_mark(const Build& b) { return b.release ? "" : " local"; }
}  // namespace

void boot_line(const Build& b, char* out, size_t n) {
    snprintf(out, n, "deck panel: boot, build %s, version %s%s", b.sha, b.version, local_mark(b));
}

void answer_line(const Build& b, char* out, size_t n) {
    snprintf(out, n, "deck panel: build %s, version %s%s", b.sha, b.version, local_mark(b));
}

void label(const Build& b, char* out, size_t n) { snprintf(out, n, "v%s%s  %s", b.version, local_mark(b), b.sha); }

}  // namespace build_info
