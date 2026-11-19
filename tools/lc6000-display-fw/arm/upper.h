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
/// Sector 8: B's room until a larger B is needed.
#define UPPER_LIMIT 0x20000u
#define UPPER_MARKER 0x42574644u /* "DFWB" */
#define UPPER_VERSION 1u
#define UPPER_HEADER 20u

/// B's draw entry (a Thumb address on the chip) if the B at `b`, which the chip sees at UPPER_BASE, checks out:
/// marker, version, length, CRC and an entry inside B. Otherwise 0. Reads nothing past the marker of an erased B.
uint32_t upper_check(const uint8_t *b);

#endif
