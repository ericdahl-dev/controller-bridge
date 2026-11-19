#!/usr/bin/env python3
"""Patch an LC6000 PRIME wd firmware image inside its DfuSe file, and fix its checksums.

Standard library only. Run with python3 -I. See README.md in this folder."""
import struct, zlib
from dataclasses import dataclass

PREFIX_SIZE = 11
TARGET_PREFIX_SIZE = 274
ELEMENT_HEADER_SIZE = 8
SUFFIX_SIZE = 16

TRAILER_SIZE = 32
TRAILER_MAGIC = 0xDEADBEEF
END_TOKEN = b"EndOfFlashToken\x00"
TP_REFUSAL = ("this image has no CRC trailer this tool understands (no 0xDEADBEEF magic, length and CRC). "
              "That is the tp (top panel) layout: its trailer field is undecoded, so a patched tp image "
              "can't be given a trailer the bootloader would accept. Only wd images can be patched")


class Refused(Exception):
    """The input or the patch isn't one this tool can handle safely."""


@dataclass
class DfuSeImage:
    address: int
    element: bytes
    head: bytes  # everything before the element bytes, kept verbatim
    suffix_head: bytes  # the suffix minus its CRC, kept verbatim


def suffix_crc(data):
    return zlib.crc32(data) ^ 0xFFFFFFFF


def stm32_crc(data, crc=0xFFFFFFFF):
    """The STM32 hardware CRC unit: CRC-32 poly 0x04C11DB7, from 0xFFFFFFFF, little-endian 32-bit words,
    no reflection, no final XOR."""
    if len(data) % 4:
        raise ValueError("the STM32 CRC unit takes whole 32-bit words")
    for (word,) in struct.iter_unpack("<I", data):
        crc ^= word
        for _ in range(32):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
    return crc


def covered_length(element):
    """The number of bytes the wd trailer CRC covers, once the trailer is known good. Refuses anything else."""
    size = len(element)
    if size < TRAILER_SIZE or size % 4 or element[-16:] != END_TOKEN:
        raise Refused("the image doesn't end with the 32-byte EndOfFlashToken trailer")
    magic, covered, stored = struct.unpack_from("<III", element, size - 28)
    if magic != TRAILER_MAGIC or covered != size - 20:
        raise Refused(TP_REFUSAL)
    if stm32_crc(element[:covered]) != stored:
        raise Refused("the input's trailer CRC doesn't match its image: refusing to build on it")
    return covered


def build(image, element):
    """Serialises the DfuSe file around a new element of the same size, with a fresh suffix CRC."""
    data = image.head + element + image.suffix_head
    return data + struct.pack("<I", suffix_crc(data))


def parse_patch(patch_text):
    """A patch description: one `ADDRESS OLD-HEX NEW-HEX` per line, `#` starts a comment.
    Returns (address, old bytes, new bytes) tuples."""
    edits = []
    for number, line in enumerate(patch_text.splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        try:
            address, old, new = line.split()
            edit = (int(address, 16), bytes.fromhex(old), bytes.fromhex(new))
        except ValueError:
            raise Refused(f"patch line {number} isn't `ADDRESS OLD-HEX NEW-HEX`: {line!r}") from None
        if not edit[1] or len(edit[1]) != len(edit[2]):
            raise Refused(f"patch line {number}: old and new bytes must have the same, non-zero length")
        edits.append(edit)
    return edits


def apply_edits(element, address, edits):
    """Writes each edit into the element after checking its old bytes. Never touches the trailer."""
    trailer_start = address + len(element) - TRAILER_SIZE
    taken = []
    for at, old, new in edits:
        end = at + len(old)
        if at < address or end > address + len(element):
            raise Refused(f"patch at 0x{at:08X} is outside the image (0x{address:08X}-0x{address + len(element):08X})")
        if end > trailer_start:
            raise Refused(f"patch at 0x{at:08X} reaches into the trailer at 0x{trailer_start:08X}; the tool writes it")
        if any(at < other_end and other_at < end for other_at, other_end in taken):
            raise Refused(f"patch at 0x{at:08X} overlaps another patch line")
        taken.append((at, end))
        offset = at - address
        if element[offset:offset + len(old)] != old:
            found = element[offset:offset + len(old)].hex()
            raise Refused(f"old bytes at 0x{at:08X} are {found}, not {old.hex()}: wrong image or wrong patch")
        element[offset:offset + len(new)] = new


def patch(data, patch_text):
    """Applies a patch description to a wd DfuSe file and returns the new file, both CRCs recomputed."""
    image = parse(data)
    covered = covered_length(image.element)
    element = bytearray(image.element)
    apply_edits(element, image.address, parse_patch(patch_text))
    struct.pack_into("<I", element, covered, stm32_crc(bytes(element[:covered])))
    return build(image, bytes(element))


def parse(data):
    """Reads a one-target, one-element DfuSe file. Refuses anything else."""
    if len(data) < PREFIX_SIZE + TARGET_PREFIX_SIZE + ELEMENT_HEADER_SIZE + SUFFIX_SIZE or data[:5] != b"DfuSe":
        raise Refused("not a DfuSe file")
    if suffix_crc(data[:-4]) != struct.unpack_from("<I", data, len(data) - 4)[0]:
        raise Refused("the DfuSe suffix CRC doesn't match the file")
    suffix = data[-SUFFIX_SIZE:]
    if suffix[8:11] != b"UFD" or suffix[11] != SUFFIX_SIZE:
        raise Refused("the DfuSe suffix isn't the 16-byte UFD suffix")
    version, image_size, targets = struct.unpack_from("<BIB", data, 5)
    if version != 1:
        raise Refused(f"DfuSe format version {version}, expected 1")
    if targets != 1:
        raise Refused(f"{targets} targets, expected exactly one target")
    if image_size != len(data):  # ST's tool counts the whole file, suffix included
        raise Refused("the DfuSe image size doesn't match the file length")
    if data[PREFIX_SIZE:PREFIX_SIZE + 6] != b"Target":
        raise Refused("no Target prefix where one target should start")
    target_size, elements = struct.unpack_from("<II", data, PREFIX_SIZE + 266)
    if elements != 1:
        raise Refused(f"{elements} elements, expected exactly one element")
    start = PREFIX_SIZE + TARGET_PREFIX_SIZE
    address, size = struct.unpack_from("<II", data, start)
    if target_size != ELEMENT_HEADER_SIZE + size or start + ELEMENT_HEADER_SIZE + size != len(data) - SUFFIX_SIZE:
        raise Refused("the element size doesn't match the target and file sizes")
    body = start + ELEMENT_HEADER_SIZE
    return DfuSeImage(address, bytes(data[body:body + size]), bytes(data[:body]), bytes(suffix[:-4]))
