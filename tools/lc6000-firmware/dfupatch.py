#!/usr/bin/env python3
"""Patch an LC6000 PRIME wd firmware image inside its DfuSe file, and fix its checksums.

Standard library only. Run with python3 -I. See README.md in this folder."""
import struct, zlib
from dataclasses import dataclass

PREFIX_SIZE = 11
TARGET_PREFIX_SIZE = 274
ELEMENT_HEADER_SIZE = 8
SUFFIX_SIZE = 16


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
