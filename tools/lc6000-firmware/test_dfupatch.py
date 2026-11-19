"""Tests for dfupatch.py. They build synthetic DfuSe files, so they need no vendor data.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import struct, unittest, zlib

import dfupatch

BASE = 0x08008000


def dfuse_file(element, address=BASE, *, targets=1, elements=1, vid=0x0483, pid=0xDF11):
    """A DfuSe file built straight from the UM0391 layout, independent of dfupatch."""
    body = struct.pack("<II", address, len(element)) + element
    target = b"Target" + struct.pack("<BI255sII", 0, 0, b"", len(body), elements) + body
    image_size = 11 + len(target) * targets + 16  # the whole file, suffix included, as in ST's own tool
    prefix = b"DfuSe" + struct.pack("<BIB", 1, image_size, targets)
    data = prefix + target * targets
    data += struct.pack("<HHHH", 0x0000, pid, vid, 0x011A) + b"UFD" + bytes([16])
    return data + struct.pack("<I", zlib.crc32(data) ^ 0xFFFFFFFF)


class ParseTests(unittest.TestCase):
    def test_the_image_size_field_counts_the_whole_file_with_its_suffix(self):
        data = bytearray(dfuse_file(bytes(32)))
        struct.pack_into("<I", data, 6, len(data) - 16)
        struct.pack_into("<I", data, len(data) - 4, zlib.crc32(data[:-4]) ^ 0xFFFFFFFF)
        with self.assertRaisesRegex(dfupatch.Refused, "image size"):
            dfupatch.parse(bytes(data))

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


def wd_element(size=0x400, fill=b"\x5a\xa5\x0f\xf0"):
    """A wd-style image: code, then the 32-byte trailer (version, 0xDEADBEEF, length, CRC, EndOfFlashToken)."""
    body = bytearray((fill * (size // len(fill)))[:size])
    covered = size - 20
    struct.pack_into("<4sII", body, size - 32, b"\x00\x00\x05\x00", 0xDEADBEEF, covered)
    struct.pack_into("<I", body, covered, dfupatch.stm32_crc(bytes(body[:covered])))
    body[size - 16:] = b"EndOfFlashToken\x00"
    return bytes(body)


def tp_element(size=0x400):
    """A tp-style image: its trailer has no magic and no length, just an undecoded field (an invented value here)."""
    body = bytearray(b"\xff" * size)
    struct.pack_into("<4sIII", body, size - 32, b"\x00\x00\x03\x01", 0x00C0FFEE, 0, 0)
    body[size - 16:] = b"EndOfFlashToken\x00"
    return bytes(body)


class Stm32CrcTests(unittest.TestCase):
    def test_it_matches_the_stm32_crc_unit_on_a_known_word(self):
        # ST's CRC unit fed the one word 0x12345678 from reset reads back 0xDF8A8A2B
        self.assertEqual(dfupatch.stm32_crc(struct.pack("<I", 0x12345678)), 0xDF8A8A2B)

    def test_no_words_leave_the_reset_value(self):
        self.assertEqual(dfupatch.stm32_crc(b""), 0xFFFFFFFF)


class TrailerTests(unittest.TestCase):
    def test_a_no_op_patch_gives_back_the_input_bit_for_bit(self):
        data = dfuse_file(wd_element())
        self.assertEqual(dfupatch.patch(data, ""), data)

    def test_a_tp_image_is_refused_because_its_trailer_is_undecoded(self):
        with self.assertRaisesRegex(dfupatch.Refused, "tp.*undecoded"):
            dfupatch.patch(dfuse_file(tp_element()), "")

    def test_a_stale_trailer_crc_on_the_input_is_refused(self):
        element = bytearray(wd_element())
        element[0x10] ^= 0x01
        with self.assertRaisesRegex(dfupatch.Refused, "CRC"):
            dfupatch.patch(dfuse_file(bytes(element)), "")

    def test_a_length_field_that_isnt_the_element_size_less_20_is_refused(self):
        element = bytearray(wd_element())
        struct.pack_into("<I", element, len(element) - 24, len(element) - 24)
        with self.assertRaises(dfupatch.Refused):
            dfupatch.patch(dfuse_file(bytes(element)), "")


if __name__ == "__main__":
    unittest.main()
