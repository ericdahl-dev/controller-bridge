#!/usr/bin/env python3
"""The checks the flash-day wizard's drawn path runs (#468), all on files: nothing here talks to the unit.

  python3 -I drawn_flash.py files UPPER.dfu OWNER.dfu
      Before either typed word: B's file is one element at 0x08080000 whose header checks out the way block A
      checks it, and the owner's image is a wd image at 0x08008000. So the two can't be swapped.
  python3 -I drawn_flash.py upper UPPER.dfu READ.bin
      Judges a read of all of 0x08080000-0x080FFFFF against B's file. Prints, as its first word:
        erased   nothing there yet: the gate before step 1;
        holds    exactly this B, then erased: step 1's read-back, or step 1 already done;
        replace  part of this B (a write cut off), or another B whose header and CRC check out (an older build),
                 then erased: step 1 rewrites it, behind its own typed word.
      Anything else is refused, with the first address that isn't this B.

Standard library only."""
import argparse, struct, sys, zlib

import build_upper_dfu
import dfupatch

APP_BASE = 0x08008000


def upper_block(path):
    image = dfupatch.parse(dfupatch.read(path))
    if image.address != build_upper_dfu.UPPER_BASE:
        raise dfupatch.Refused(f"{path} writes at 0x{image.address:08X}; block B's file writes at "
                               f"0x{build_upper_dfu.UPPER_BASE:08X}. Is it the owner's image?")
    try:
        build_upper_dfu.check_block(image.element)
    except dfupatch.Refused as error:
        raise dfupatch.Refused(f"{path} isn't a block B A will take: {error}") from None
    return image.element


def owner_image(path):
    image = dfupatch.parse(dfupatch.read(path))
    if image.address != APP_BASE:
        raise dfupatch.Refused(f"{path} writes at 0x{image.address:08X}; the owner's image writes at "
                               f"0x{APP_BASE:08X}. Is it block B's file?")
    if dfupatch.chip(image.element) != "wd":
        raise dfupatch.Refused(f"{path} isn't a display chip (wd) image")
    return image.element


def files(args):
    block = upper_block(args.upper)
    image = owner_image(args.owner)
    print(f"ok: block B, {len(block)} bytes at 0x{build_upper_dfu.UPPER_BASE:08X}; "
          f"the owner's image, {len(image)} bytes at 0x{APP_BASE:08X}")


def upper(args):
    block = upper_block(args.upper)
    read = dfupatch.read(args.read)
    size = build_upper_dfu.PROOF_SIZE
    if len(read) != size:
        raise dfupatch.Refused(f"the read is {len(read)} bytes, not all {size} of 0x08080000-0x080FFFFF")
    base = build_upper_dfu.UPPER_BASE
    # Where the read first leaves this B: a wrong byte, or where a cut-off write stops.
    first = next((i for i in range(len(block)) if read[i] != block[i]), None)
    if first is None:
        state, end = "holds (exactly this block B, then erased)", len(block)
    elif all(b == 0xFF for b in read[:len(block)]):
        state, end = "erased (nothing there yet)", 0
    elif all(b == 0xFF for b in read[first:len(block)]):
        state, end = "replace (part of this block B: a write cut off; rewrite it)", first
    else:
        length = other_block(read)
        if length is None:
            raise dfupatch.Refused(f"the upper flash is neither erased, this block B, nor a block B whose header and "
                                   f"CRC check out: the first byte that isn't this B is at 0x{base + first:08X}. "
                                   f"Stop; nothing is written over it")
        state, end = "replace (another block B, an older build; rewrite it)", length
    rest = next((i for i in range(end, size) if read[i] != 0xFF), None)
    if rest is not None:
        raise dfupatch.Refused(f"the upper flash holds something past where block B ends: the first other byte is "
                               f"at 0x{base + rest:08X}. Stop; nothing is written over it")
    print(state)


def other_block(read):
    """The length of a block B from any build (#516: every layout change makes a new one), if the read starts with
    one: B's marker, a length inside the upper flash, and zlib's CRC-32 from +16 matching. Its version may differ."""
    marker, _version, length, crc = struct.unpack_from("<IIII", read)
    if marker != build_upper_dfu.UPPER_MARKER or not 20 <= length <= len(read):
        return None
    return length if zlib.crc32(read[16:length]) == crc else None


def main(argv=None):
    parser = argparse.ArgumentParser(description="Checks for the drawn flash: files and reads, never the unit.")
    commands = parser.add_subparsers(dest="command", required=True)
    pair = commands.add_parser("files", help="B's file at 0x08080000 and the owner's image at 0x08008000")
    pair.add_argument("upper")
    pair.add_argument("owner")
    pair.set_defaults(run=files)
    judge = commands.add_parser("upper", help="judge a read of 0x08080000-0x080FFFFF against B's file")
    judge.add_argument("upper")
    judge.add_argument("read")
    judge.set_defaults(run=upper)
    args = parser.parse_args(argv)
    try:
        args.run(args)
    except (dfupatch.Refused, OSError) as error:
        print(f"refused: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
