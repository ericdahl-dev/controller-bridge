#!/usr/bin/env python3
"""Write block B, our drawing block for the wd's upper flash (#501), as its own DfuSe file at 0x08080000.

  python3 -I build_upper_dfu.py UPPER.bin OUT.dfu --proof ~/lc6000/wd-upper-512k.bin

Nothing here talks to the unit. Standard library only."""
import argparse, os, struct, sys, zlib

import dfupatch

UPPER_BASE = 0x08080000
# B's header (arm/upper.h): marker "DFWB", version, length, CRC-32 (zlib's) from +16 to length, the dfw_unit layout
# B was built for (#516; only block A, built from the same src/dfw.h, can judge it), the draw entry, the band entry
# (#524).
UPPER_MARKER, UPPER_VERSION, UPPER_HEADER = 0x42574644, 4, 28
UPPER_LIMIT = 0x80000  # sectors 8-11
# The owner's read covers sectors 8-11, 0x08080000-0x080FFFFF.
PROOF_SIZE = 512 * 1024
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


def check_block(block):
    """B as built (`make arm`): refused unless its header checks out the way block A will check it on the chip."""
    if len(block) < UPPER_HEADER:
        raise dfupatch.Refused(f"the block is {len(block)} bytes, shorter than B's {UPPER_HEADER}-byte header")
    marker, version, length, crc, _layout, draw, band = struct.unpack_from("<IIIIIII", block)
    if marker != UPPER_MARKER:
        raise dfupatch.Refused("the block doesn't start with B's marker \"DFWB\": it isn't block B")
    if version != UPPER_VERSION:
        raise dfupatch.Refused(f"the block is header version {version}, and block A takes version {UPPER_VERSION}")
    if length != len(block) or length > UPPER_LIMIT:
        raise dfupatch.Refused(f"the header's length {length} isn't the file's {len(block)} bytes, or is over "
                               f"the upper flash's {UPPER_LIMIT}")
    if zlib.crc32(block[16:]) != crc:
        raise dfupatch.Refused("the header's CRC doesn't match the block")
    for name, entry in (("draw", draw), ("band", band)):
        if not entry & 1 or not UPPER_BASE + UPPER_HEADER <= entry < UPPER_BASE + length:
            raise dfupatch.Refused(f"the {name} entry 0x{entry:08X} isn't Thumb code inside the block")


def check_proof(path):
    """The owner's read of the upper flash, which says sector 8 exists and is empty. Refuses unless it checks out."""
    if path is None:
        raise dfupatch.Refused("--proof is required: the owner's read-only read of the upper flash "
                               "(README, \"Read-only checks\"); B is never flashed before it")
    if dfupatch.inside(path, dfupatch.repository_root()):
        raise dfupatch.Refused("the proof must be the owner's own read, kept outside the repository (~/lc6000)")
    proof = dfupatch.read(path)
    if len(proof) != PROOF_SIZE:
        raise dfupatch.Refused(f"the proof is {len(proof)} bytes, not the {PROOF_SIZE} of a whole read of "
                               "0x08080000-0x080FFFFF: the upper flash isn't shown to exist")
    if proof.count(0xFF) != PROOF_SIZE:
        first = next(i for i, byte in enumerate(proof) if byte != 0xFF)
        raise dfupatch.Refused(f"the upper flash isn't all erased (0xFF): the first other byte is at "
                               f"0x{UPPER_BASE + first:08X}. Stop and post this; nothing goes there until it's "
                               "understood")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Write block B as its own DfuSe file at 0x08080000.")
    parser.add_argument("block")
    parser.add_argument("output")
    parser.add_argument("--proof", help="the owner's read-only read of 0x08080000-0x080FFFFF (wd-upper-512k.bin)")
    args = parser.parse_args(argv)
    try:
        check_proof(args.proof)
        if dfupatch.inside(args.output, dfupatch.repository_root()):
            raise dfupatch.Refused("write B's DfuSe file outside the repository: built images are never committed")
        if os.path.exists(args.output):
            raise dfupatch.Refused(f"{args.output} already exists; not overwriting it")
        block = dfupatch.read(args.block)
        check_block(block)
        out = dfuse(block)
        with open(args.output, "xb") as f:
            f.write(out)
    except (dfupatch.Refused, OSError) as error:
        print(f"refused: {error}", file=sys.stderr)
        return 1
    print(f"wrote {args.output}: block B, {len(out)} bytes, at 0x{UPPER_BASE:08X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
