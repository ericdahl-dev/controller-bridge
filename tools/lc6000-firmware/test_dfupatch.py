"""Tests for dfupatch.py. They build synthetic DfuSe files, so they need no vendor data.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import struct, unittest, zlib

import dfupatch

BASE = 0x08008000


def dfuse_file(element, address=BASE, *, targets=1, elements=1, vid=0x0483, pid=0xDF11):
    """A DfuSe file built straight from the UM0391 layout, independent of dfupatch."""
    body = struct.pack("<II", address, len(element)) + element
    target = b"Target" + struct.pack("<BI255sII", 0, 0, b"", len(body), elements) + body
    image_size = 11 + len(target) * targets
    prefix = b"DfuSe" + struct.pack("<BIB", 1, image_size, targets)
    data = prefix + target * targets
    data += struct.pack("<HHHH", 0x0000, pid, vid, 0x011A) + b"UFD" + bytes([16])
    return data + struct.pack("<I", zlib.crc32(data) ^ 0xFFFFFFFF)


class ParseTests(unittest.TestCase):
    def test_it_reads_the_one_element_address_and_bytes(self):
        image = dfupatch.parse(dfuse_file(b"\x01\x02\x03\x04" * 8, address=0x08008000))
        self.assertEqual(image.address, 0x08008000)
        self.assertEqual(image.element, b"\x01\x02\x03\x04" * 8)

    def test_a_wrong_suffix_crc_is_refused(self):
        data = bytearray(dfuse_file(bytes(32)))
        data[-1] ^= 0xFF
        with self.assertRaisesRegex(dfupatch.Refused, "suffix CRC"):
            dfupatch.parse(bytes(data))

    def test_a_file_that_is_not_dfuse_is_refused(self):
        with self.assertRaisesRegex(dfupatch.Refused, "DfuSe"):
            dfupatch.parse(b"\x00" * 64)

    def test_more_than_one_target_or_element_is_refused(self):
        # the stock updater reads the element at a fixed offset (0x11D), so anything else would flash wrongly
        with self.assertRaisesRegex(dfupatch.Refused, "target"):
            dfupatch.parse(dfuse_file(bytes(32), targets=2))
        with self.assertRaisesRegex(dfupatch.Refused, "element"):
            dfupatch.parse(dfuse_file(bytes(32), elements=2))

    def test_a_truncated_file_is_refused(self):
        data = dfuse_file(bytes(64))
        cut = data[:200] + data[-16:-4]
        cut += struct.pack("<I", zlib.crc32(cut) ^ 0xFFFFFFFF)
        with self.assertRaises(dfupatch.Refused):
            dfupatch.parse(cut)


if __name__ == "__main__":
    unittest.main()
