#!/usr/bin/env python3
"""Builds the LC6000 jog-display upload (#121, #165): a 198x198 PNG in, a jogseq plan out.

  python3 -I jogbuild.py png  <in.png> <out.png>     re-encode for the unit: rotated 180°, the PNG layout it accepts
  python3 -I jogbuild.py plan <in.png> <out.plan> [slot]   the host + upload + commit + show plan for jogseq (slot 1)
  python3 -I jogbuild.py selftest                    encoder round trips, no device

The recipe, as verified on hardware (see #121's recipe comment):
  CTL  F0 00 02 0B 7F 10 60 00 04 04 01 01 00 F7, then F0 00 20 7F 01 F7      host hello (without it: ack 06)
  (0C's three bytes are only the 21-bit size; the slot is 0E's first byte and 0A's image index.)
  WD   90 01 00, 0A 01 00 06 0D, 0C <size>, 0D <offset + 7-bit data>…, 0E <slot + byte-sum>
  WD   wait for the 01 10 0F 00 01 00 acks (06 = refused), then 7E 00 06 01, 10 (commit; unit answers 01 10 10)
  WD   0A … 01 00 <slot> 0D                                                    show the uploaded slot (djay: 01 logo, 02 cover art)
Frame: F0 00 02 0B <target 7F> 10 <cmd> <len, 14-bit> <payload> F7.
"""
import struct
import sys
import zlib

HEAD = [0x00, 0x02, 0x0B, 0x7F, 0x10]
SIZE = 198
CHUNK = 14332   # the most image bytes whose 7-bit form (n*8//7 + 1) plus a 3-byte offset fits a 14-bit length

HOST_HELLO = [
    [0xF0, 0x00, 0x02, 0x0B, 0x7F, 0x10, 0x60, 0x00, 0x04, 0x04, 0x01, 0x01, 0x00, 0xF7],
    [0xF0, 0x00, 0x20, 0x7F, 0x01, 0xF7],
]
HOST_GOODBYE = [0xF0, 0x00, 0x20, 0x7F, 0x02, 0xF7]
SHOW_BLANK = [0x01, 0x00, 0x06, 0x0D]     # 0A before an upload: image index 06


def show(slot):
    """0A after the commit: show image index `slot`, the upload's slot (djay: 01 for its logo, 02 for cover art)."""
    return [0x01, 0x00, slot, 0x0D]


def frame(cmd, payload):
    n = len(payload)
    return [0xF0, *HEAD, cmd, n >> 7, n & 0x7F, *payload, 0xF7]


def u21(value):
    return [(value >> 14) & 0x7F, (value >> 7) & 0x7F, value & 0x7F]


def bits7(data):
    """MSB-first bitstream into 7-bit bytes, zero-padded: len(data)*8//7 + 1 bytes."""
    out, acc, nbits = [], 0, 0
    for byte in data:
        acc, nbits = (acc << 8) | byte, nbits + 8
        while nbits >= 7:
            nbits -= 7
            out.append((acc >> nbits) & 0x7F)
    out.append((acc << (7 - nbits)) & 0x7F if nbits else 0)
    return out


def commit_0e(png, slot=1):
    """0E: the slot, then the PNG's 32-bit byte-sum as 8 nibbles, most significant first."""
    total = sum(png) & 0xFFFFFFFF
    return [slot] + [(total >> shift) & 0x0F for shift in range(28, -4, -4)]


def upload(png, slot=1):
    """0A (index 06), 0C size, 0D chunks, 0E checksum, 10 commit."""
    msgs = [frame(0x0A, SHOW_BLANK), frame(0x0C, u21(len(png)))]
    for offset in range(0, len(png), CHUNK):
        msgs.append(frame(0x0D, u21(offset) + bits7(png[offset:offset + CHUNK])))
    msgs += [frame(0x0E, commit_0e(png, slot)), frame(0x10, [])]
    return msgs


# PNG in and out. Only 8-bit RGB and RGBA, not interlaced: what this tool makes and reads.

def chunks(png):
    pos = 8
    while pos < len(png):
        n, kind = struct.unpack('>I4s', png[pos:pos + 8])
        yield kind, png[pos + 8:pos + 8 + n]
        pos += 12 + n


def decode_rgba(png):
    """Rows of RGBA bytes from an 8-bit RGB or RGBA PNG."""
    header = dict(chunks(png))[b'IHDR']
    width, height, depth, kind, _, _, interlace = struct.unpack('>IIBBBBB', header)
    if depth != 8 or kind not in (2, 6) or interlace:
        raise SystemExit(f"need an 8-bit RGB or RGBA PNG, not interlaced (got depth {depth}, type {kind})")
    bpp = 4 if kind == 6 else 3
    raw = zlib.decompress(b''.join(body for k, body in chunks(png) if k == b'IDAT'))
    stride, rows, prev = width * bpp, [], bytearray(width * bpp)
    for y in range(height):
        kind_ = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if kind_ == 1:
                line[i] = (line[i] + a) & 255
            elif kind_ == 2:
                line[i] = (line[i] + b) & 255
            elif kind_ == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif kind_ == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        rows.append(bytes(line) if bpp == 4 else b''.join(bytes(line[i:i + 3]) + b'\xff' for i in range(0, stride, 3)))
    return width, height, rows


def rotate180(rows):
    """The unit shows uploads rotated 180° (#121's F test), so they're sent pre-rotated."""
    return [b''.join(row[i:i + 4] for i in range(len(row) - 4, -4, -4)) for row in reversed(rows)]


def _chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))


def exif_dimensions(width, height):
    """A minimal eXIf: a big-endian TIFF header, an Exif IFD pointer, and PixelX/YDimension (as on the tested files)."""
    tiff = b'MM\x00\x2a' + struct.pack('>I', 8)
    ifd0 = struct.pack('>H', 1) + struct.pack('>HHII', 0x8769, 4, 1, 26) + struct.pack('>I', 0)
    exif = struct.pack('>H', 2) + struct.pack('>HHII', 0xA002, 4, 1, width) + struct.pack('>HHII', 0xA003, 4, 1, height)
    return tiff + ifd0 + exif + struct.pack('>I', 0)


def encode(width, height, rows):
    """RGBA PNG laid out as the unit has accepted: IHDR, sRGB, eXIf, IDAT in 16384-byte pieces of a
    several-block zlib stream (level 1), IEND. Row filter 0."""
    raw = b''.join(b'\x00' + row for row in rows)
    compressor = zlib.compressobj(1, zlib.DEFLATED, 15, 1)
    data = compressor.compress(raw) + compressor.flush()
    png = b'\x89PNG\r\n\x1a\n' + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += _chunk(b'sRGB', b'\x00') + _chunk(b'eXIf', exif_dimensions(width, height))
    for i in range(0, len(data), 16384):
        png += _chunk(b'IDAT', data[i:i + 16384])
    return png + _chunk(b'IEND', b'')


def for_unit(png):
    width, height, rows = decode_rgba(png)
    if (width, height) != (SIZE, SIZE):
        raise SystemExit(f"the jog display takes {SIZE}x{SIZE}, not {width}x{height}")
    return encode(width, height, rotate180(rows))


def hexs(msg):
    return ' '.join(f'{b:02X}' for b in msg)


def plan(png, slot=1):
    """A jogseq plan: hello, upload into `slot`, wait for the acks, commit, show that slot."""
    msgs = upload(png, slot)
    body, commit = msgs[:-1], msgs[-1]
    lines = [f"# LC6000 jog upload (#121): host hello, upload to slot {slot}, acks, commit, show index {slot}"]
    lines += [f"0 CTL {hexs(m)}" for m in HOST_HELLO]
    lines.append("0 WD 90 01 00")
    lines += [f"{8 if i == 1 else 0} WD {hexs(m)}" for i, m in enumerate(body)]
    # Each upload message but one is acked: the count seen on hardware.
    lines.append(f"0 ACKS {len(body) - 1} 20000")
    lines.append(f"0 WD {hexs([0xF0, 0x7E, 0x00, 0x06, 0x01, 0xF7])}")
    lines.append(f"10 WD {hexs(commit)}")
    lines.append(f"500 WD {hexs(frame(0x0A, show(slot)))}")
    return '\n'.join(lines) + '\n'


def selftest():
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sysex_decode
    rows = [b''.join(bytes([x, y, (x * y) & 255, 255]) for x in range(SIZE)) for y in range(SIZE)]
    png = encode(SIZE, SIZE, rows)
    assert decode_rgba(png)[2] == rows, "PNG round trip"
    assert rotate180(rotate180(rows)) == rows, "two half turns are none"
    assert rotate180(rows)[0][:4] == rows[-1][-4:], "the last pixel comes first"
    assert sysex_decode.unbits(bits7(png))[:len(png)] == png, "7-bit bitstream round trip"
    messages = [("?", m) for m in upload(png)]
    assert sysex_decode.lc6000_images(messages) == [png], "upload rebuilds to the same PNG"
    assert commit_0e(bytes([1, 2, 3])) == [1, 0, 0, 0, 0, 0, 0, 0, 6], "byte-sum as nibbles"
    assert commit_0e(bytes([0xFF] * 0x3AEE))[1:] == [(0x3AEE * 0xFF >> s) & 0xF for s in range(28, -4, -4)]
    slot2 = plan(png, slot=2)
    assert "7F 10 0E 00 09 02 " in slot2, "0E names the slot"
    assert slot2.rstrip().endswith("7F 10 0A 00 04 01 00 02 0D F7"), "the show index is the slot"
    print("selftest ok:", len(png), "byte PNG,", len(messages), "messages")


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == 'selftest':
        selftest()
    elif len(sys.argv) in (4, 5) and sys.argv[1] in ('png', 'plan'):
        source = open(sys.argv[2], 'rb').read()
        if sys.argv[1] == 'png':
            open(sys.argv[3], 'wb').write(for_unit(source))
        else:
            open(sys.argv[3], 'w').write(plan(for_unit(source), slot=int(sys.argv[4]) if len(sys.argv) == 5 else 1))
    else:
        print(__doc__)
        sys.exit(2)
