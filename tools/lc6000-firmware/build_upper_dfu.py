#!/usr/bin/env python3
"""Write block B, our drawing block for the wd's upper flash (#501), as its own DfuSe file at 0x08080000.

  python3 -I build_upper_dfu.py UPPER.bin OUT.dfu --proof ~/lc6000/wd-upper-512k.bin

Nothing here talks to the unit. Standard library only."""
import argparse, struct, sys

import dfupatch

UPPER_BASE = 0x08080000
# The ST ROM bootloader's USB IDs, which the owner's unit shows in update mode (README, "Read-only checks"). Any
# bcdDevice (0xFFFF).
VID, PID = 0x0483, 0xDF11


def dfuse(block):
    """One target (alt 0, internal flash), one element: B at UPPER_BASE (UM0391 layout)."""
    body = struct.pack("<II", UPPER_BASE, len(block)) + block
    target = b"Target" + struct.pack("<BI255sII", 0, 0, b"", len(body), 1) + body
    prefix = b"DfuSe" + struct.pack("<BIB", 1, dfupatch.PREFIX_SIZE + len(target) + dfupatch.SUFFIX_SIZE, 1)
    data = prefix + target + struct.pack("<HHHH", 0xFFFF, PID, VID, 0x011A) + b"UFD" + bytes([dfupatch.SUFFIX_SIZE])
    return data + struct.pack("<I", dfupatch.suffix_crc(data))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Write block B as its own DfuSe file at 0x08080000.")
    parser.add_argument("block")
    parser.add_argument("output")
    parser.add_argument("--proof", help="the owner's read-only read of 0x08080000-0x080FFFFF (wd-upper-512k.bin)")
    args = parser.parse_args(argv)
    try:
        out = dfuse(dfupatch.read(args.block))
        with open(args.output, "xb") as f:
            f.write(out)
    except (dfupatch.Refused, OSError) as error:
        print(f"refused: {error}", file=sys.stderr)
        return 1
    print(f"wrote {args.output}: block B, {len(out)} bytes, at 0x{UPPER_BASE:08X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
