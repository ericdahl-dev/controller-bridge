#!/usr/bin/env python3
"""Seal block B (#501): fill in its header's length (+8) and CRC (+12, zlib's CRC-32 of B from +16 to its end).

  python3 -I arm/upper_seal.py upper.bin

Standard library only."""
import struct, sys, zlib

MARKER, LIMIT = 0x42574644, 0x80000


def seal(data):
    data = bytearray(data)
    if len(data) < 20 or struct.unpack_from("<I", data)[0] != MARKER:
        raise SystemExit("upper_seal: this isn't block B: no \"DFWB\" header at its start")
    if len(data) > LIMIT:
        raise SystemExit(f"upper_seal: block B is {len(data)} bytes, over the upper flash's {LIMIT}")
    struct.pack_into("<I", data, 8, len(data))
    struct.pack_into("<I", data, 12, zlib.crc32(bytes(data[16:])))
    return bytes(data)


if __name__ == "__main__":
    path = sys.argv[1]
    with open(path, "rb") as f:
        sealed = seal(f.read())
    with open(path, "wb") as f:
        f.write(sealed)
    print(f"block B: {len(sealed)} of {LIMIT} bytes used")
