#!/usr/bin/env python3
"""Decoder for LC6000 jog-display SysEx (#121): splits a MIDI Monitor capture into messages and rebuilds image uploads.

Input: a MIDI Monitor text export (File > Export, or copy-paste of the event list with
"Show SysEx data as hex"), or a raw .syx dump (MIDI Monitor > Save SysEx). Any text whose
lines carry hex byte pairs works: SysEx spanning several lines is joined until F7.

  python3 -I sysex-decode.py capture.txt            # summary
  python3 -I sysex-decode.py capture.syx --dump out # also write payload bursts, decoded

What it prints:
  1. Each SysEx split out, grouped by header. Denon/inMusic (00 02 0B) is parsed as the Prime 4
     layout (github.com/whanake-music/denon-prime-4-analysis):
       F0 00 02 0B <target> <class> <cmd> <lenHi> <lenLo> <payload…> F7
     with len a 14-bit count of payload bytes; a mismatch is flagged.
  2. Bursts: runs of the same (target, class, cmd) back to back, with their total payload.
  3. Image guesses: each burst's payload size against WxH x bytes-per-pixel under the
     packings a 7-bit SysEx stream can use (nibbles, 7-in-8, raw 7-bit).
No device I/O: this only reads a file.
"""
import re
import sys
from collections import OrderedDict, defaultdict
from pathlib import Path

DENON = (0x00, 0x02, 0x0B)
SIZES = [(320, 320), (240, 240), (480, 480), (360, 360), (128, 128), (320, 240), (240, 320)]
FORMATS = [("RGB565", 2), ("RGB888", 3), ("ARGB8888", 4), ("gray8", 1), ("gray4", 0.5), ("mono1", 0.125)]
# Bytes on the wire per byte of image data, for each 7-bit packing.
PACKINGS = [("nibbles (2 wire B per B)", 2.0), ("7-in-8 (8 per 7)", 8 / 7), ("raw 7-bit", 1.0)]

HEX = re.compile(r"\b[0-9A-Fa-f]{2}\b")


def read_mmon(data):
    """A MIDI Monitor document: a plist whose messageData is a keyed archive of SMMessages."""
    import plistlib
    archive = plistlib.loads(plistlib.loads(data)["messageData"])
    objects = archive["$objects"]
    deref = lambda u: objects[u.data] if isinstance(u, plistlib.UID) else u
    chunks = []
    for u in deref(archive["$top"]["root"])["NS.objects"]:
        m = deref(u)
        if deref(m["$class"])["$classname"] == "SMSystemExclusiveMessage":
            chunks.append(("?", [0xF0, *deref(m.get("data", b"")), 0xF7]))
    return chunks


def read_bytes(path):
    """Returns [(direction, bytes)] chunks. Binary .syx is one chunk; text is one per line."""
    data = Path(path).read_bytes()
    if data.startswith(b"bplist00"):
        return read_mmon(data)
    if data[:1] == b"\xF0":
        return [("?", list(data))]
    chunks = []
    for line in data.decode("utf-8", "replace").splitlines():
        lower = line.lower()
        direction = "to" if re.search(r"\bto\b", lower) else "from" if re.search(r"\bfrom\b", lower) else "?"
        # Only the hex run that holds SysEx bytes: drop timestamps like 12:34:56.789.
        tokens = [int(t, 16) for t in HEX.findall(re.sub(r"\d+:\d+:\d+(\.\d+)?", " ", line))]
        if tokens:
            chunks.append((direction, tokens))
    return chunks


def split_sysex(chunks):
    """Yields (direction, message) for each F0…F7, joining messages that span chunks."""
    current, direction = None, "?"
    for d, data in chunks:
        for b in data:
            if b == 0xF0:
                current, direction = [b], d
            elif current is not None:
                current.append(b)
                if b == 0xF7:
                    yield direction, current
                    current = None
    if current:
        yield direction, current + ["(unterminated)"]


def parse(msg):
    body = [b for b in msg[1:] if isinstance(b, int) and b != 0xF7]
    if not body:
        return {"maker": "empty"}
    if body[0] == 0x00 and len(body) >= 3:
        maker, rest = tuple(body[:3]), body[3:]
    else:
        maker, rest = (body[0],), body[1:]
    info = {"maker": " ".join(f"{b:02X}" for b in maker), "rest": rest}
    if maker == DENON and len(rest) >= 5:
        target, cls, cmd, hi, lo = rest[:5]
        payload = rest[5:]
        declared = (hi << 7) | lo
        info.update(key=(target, cls, cmd), payload=payload, declared=declared, ok=declared == len(payload))
    elif maker == (0x7E,) or maker == (0x7F,):
        info.update(key=("universal", *rest[:3]), payload=rest)
    else:
        info.update(key=tuple(rest[:3]), payload=rest)
    return info


def hexs(bs, limit=24):
    s = " ".join(f"{b:02X}" for b in bs[:limit])
    return s + (f" … (+{len(bs) - limit})" if len(bs) > limit else "")


def image_guesses(n):
    out = []
    for (w, h) in SIZES:
        for fmt, bpp in FORMATS:
            raw = w * h * bpp
            for pack, factor in PACKINGS:
                wire = raw * factor
                if wire and abs(n - wire) / wire < 0.02:
                    out.append((abs(n - int(wire)), f"{w}x{h} {fmt}, {pack}: expect {int(wire)} B ({n - int(wire):+d})"))
    return [text for _, text in sorted(out, key=lambda t: t[0])]


def unnibble(p):
    return bytes(((p[i] & 0x0F) << 4) | (p[i + 1] & 0x0F) for i in range(0, len(p) - 1, 2))


def unpack78(p):
    """MSB-first 7-in-8: a header byte holds bit 7 of the next seven bytes (Roland/Elektron style)."""
    out = bytearray()
    for i in range(0, len(p), 8):
        group = p[i:i + 8]
        if not group:
            break
        msbs = group[0]
        for j, b in enumerate(group[1:]):
            out.append(b | (((msbs >> (6 - j)) & 1) << 7))
    return bytes(out)


def unbits(seven):
    """MSB-first bitstream: 7 bits from each byte, back to back, read as 8-bit bytes (#121)."""
    acc = nbits = 0
    out = bytearray()
    for b in seven:
        acc, nbits = (acc << 7) | (b & 0x7F), nbits + 7
        if nbits >= 8:
            nbits -= 8
            out.append((acc >> nbits) & 0xFF)
    return bytes(out)


def lc6000_images(messages):
    """The LC6000 jog image upload (#121): 0C <21-bit size>, then 0D chunks of
    <21-bit offset into the image> + MSB-first 7-bit bitstream. The image is a PNG."""
    images, size, image = [], None, bytearray()
    for _, m in messages:
        info = parse(m)
        key, p = info.get("key"), info.get("payload", [])
        if info["maker"] != "00 02 0B" or not key or len(p) < 3:
            continue
        value = (p[0] << 14) | (p[1] << 7) | p[2]
        if key[2] == 0x0C:
            size, image = value, bytearray()
        elif key[2] == 0x0D and size is not None:
            if value != len(image):
                print(f"  chunk offset {value} != {len(image)} so far: gap or reorder")
            image += unbits(p[3:])
            if len(image) >= size:
                images.append(bytes(image[:size]))
                size = None
    return images


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    dump = Path(argv[argv.index("--dump") + 1]) if "--dump" in argv else None
    messages = list(split_sysex(read_bytes(argv[1])))
    print(f"{len(messages)} SysEx messages\n")

    groups = OrderedDict()
    for d, m in messages:
        info = parse(m)
        k = (d, info["maker"], info.get("key"))
        g = groups.setdefault(k, {"n": 0, "sizes": defaultdict(int), "first": m, "bad": 0})
        g["n"] += 1
        g["sizes"][len(m)] += 1
        g["bad"] += 0 if info.get("ok", True) else 1

    print("== Groups (direction, maker, key = target/class/cmd for Denon) ==")
    for (d, maker, key), g in groups.items():
        k = " ".join(f"{x:02X}" if isinstance(x, int) else str(x) for x in (key or ()))
        sizes = ", ".join(f"{s} B x{c}" for s, c in sorted(g["sizes"].items())[:6])
        flag = f"  LEN MISMATCH x{g['bad']}" if g["bad"] else ""
        print(f"{d:>4} {maker:8} [{k}] x{g['n']}  sizes: {sizes}{flag}")
        print(f"       first: {hexs(g['first'])}")

    print("\n== Bursts (same key back to back) ==")
    bursts = []
    for d, m in messages:
        info = parse(m)
        k = (d, info["maker"], info.get("key"))
        if bursts and bursts[-1]["k"] == k:
            bursts[-1]["msgs"] += 1
            bursts[-1]["payload"] += info.get("payload", [])
        else:
            bursts.append({"k": k, "msgs": 1, "payload": list(info.get("payload", []))})
    for i, b in enumerate(bursts):
        d, maker, key = b["k"]
        k = " ".join(f"{x:02X}" if isinstance(x, int) else str(x) for x in (key or ()))
        n = len(b["payload"])
        line = f"#{i:<3} {d:>4} {maker} [{k}] {b['msgs']} msgs, {n} payload B"
        print(line)
        for guess in image_guesses(n) if n > 1000 else []:
            print(f"       image? {guess}")
        if dump and n > 1000:
            dump.mkdir(parents=True, exist_ok=True)
            base = dump / f"burst{i:03d}"
            Path(f"{base}.raw").write_bytes(bytes(b["payload"]))
            Path(f"{base}.nib").write_bytes(unnibble(b["payload"]))
            Path(f"{base}.78").write_bytes(unpack78(b["payload"]))
    images = lc6000_images(messages)
    if images:
        print("\n== LC6000 jog image uploads (0C size, 0D offset + 7-bit bitstream) ==")
    for i, image in enumerate(images):
        kind = "PNG" if image[:8] == b"\x89PNG\r\n\x1a\n" else "unknown"
        dims = f" {int.from_bytes(image[16:20], 'big')}x{int.from_bytes(image[20:24], 'big')}" if kind == "PNG" else ""
        print(f"image {i}: {len(image)} B, {kind}{dims}, head {image[:8].hex()}")
        if dump:
            dump.mkdir(parents=True, exist_ok=True)
            (dump / f"image{i}.{'png' if kind == 'PNG' else 'bin'}").write_bytes(image)
    if dump:
        print(f"\nPayloads in {dump}/: .raw as sent, .nib nibble-joined, .78 7-in-8 unpacked.")
        print("View one: ffmpeg -f rawvideo -pixel_format rgb565le -video_size 320x320 -i burst000.nib out.png")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
