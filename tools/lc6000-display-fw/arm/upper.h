// Block B, our drawing block in the wd's upper flash (#501). It starts at 0x08080000 (sector 8, outside Denon's
// image) with a header block A checks before it calls anything in B. All fields are little-endian 32-bit words:
//
//   +0  marker   "DFWB"
//   +4  version  UPPER_VERSION; changes whenever A and B's shared layout (dfw_unit, the entry table) changes
//   +8  length   all of B in bytes, header included
//   +12 crc      CRC-32 (zlib's) of B from +16 (the entry table on) up to length
//   +16 draw     the entry table: B's draw function, a Thumb address inside B
//
// Portable C: it reads bytes only, so it runs and is tested on the Mac.
#ifndef UPPER_H
#define UPPER_H
#include <stdint.h>

#define UPPER_BASE 0x08080000u
/// Sectors 8-11 (128 KB each), 0x08080000-0x080FFFFF: all of the upper flash, once the owner's read proves it.
#define UPPER_LIMIT 0x80000u
#define UPPER_MARKER 0x42574644u /* "DFWB" */
#define UPPER_VERSION 1u
#define UPPER_HEADER 20u

/// How much of B's check one main-loop tick does: about 0.7 ms at 180 MHz (11 instructions a byte, measured).
#define UPPER_CHUNK 8192u

enum { UPPER_NONE = 0, UPPER_CHECKING, UPPER_GOOD, UPPER_BAD };

/// A check of B in progress, so it can run a chunk per tick from boot and be done before the app's first ask.
typedef struct {
    uint8_t status;
    uint32_t done;
    uint32_t length;
    uint32_t crc;
    uint32_t entry;
} upper_progress;

/// Starts checking the B at `b`: the header's marker, version and length now; the CRC and entry in steps.
void upper_start(upper_progress *progress, const uint8_t *b);
/// Checks up to `budget` more of B's bytes. Returns the status: still UPPER_CHECKING, or UPPER_GOOD or UPPER_BAD.
uint8_t upper_step(upper_progress *progress, const uint8_t *b, uint32_t budget);

/// B's draw entry (a Thumb address on the chip) if the B at `b`, which the chip sees at UPPER_BASE, checks out:
/// marker, version, length, CRC and an entry inside B. Otherwise 0. Reads nothing past the marker of an erased B.
uint32_t upper_check(const uint8_t *b);

#endif
