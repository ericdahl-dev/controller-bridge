"""Tests for dfupatch.py. They build synthetic DfuSe files, so they need no vendor data.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import contextlib, io, os, shutil, struct, subprocess, tempfile, unittest, zlib

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


def changed_offsets(a, b):
    return [i for i in range(len(a)) if a[i] != b[i]]


class PatchTests(unittest.TestCase):
    def setUp(self):
        self.element = wd_element()
        self.data = dfuse_file(self.element)
        self.element_start = len(self.data) - 16 - len(self.element)

    def test_a_one_byte_patch_changes_only_that_byte_the_trailer_crc_and_the_suffix_crc(self):
        old = self.element[0x40]
        out = dfupatch.patch(self.data, f"# one byte\n0x{BASE + 0x40:08X} {old:02x} {old ^ 0xFF:02x}\n")
        self.assertEqual(len(out), len(self.data))
        crc_at = self.element_start + len(self.element) - 20
        allowed = {self.element_start + 0x40, *range(crc_at, crc_at + 4), *range(len(out) - 4, len(out))}
        self.assertTrue(set(changed_offsets(self.data, out)) <= allowed)
        self.assertIn(self.element_start + 0x40, changed_offsets(self.data, out))
        self.assertEqual(dfupatch.patch(out, ""), out)  # its trailer and suffix now check out

    def test_old_bytes_that_dont_match_are_refused(self):
        wrong = self.element[0x40] ^ 0x01
        with self.assertRaisesRegex(dfupatch.Refused, "old bytes"):
            dfupatch.patch(self.data, f"0x{BASE + 0x40:08X} {wrong:02x} 00")

    def test_a_patch_that_touches_the_trailer_is_refused(self):
        at = len(self.element) - 32
        old = self.element[at:at + 4].hex()
        with self.assertRaisesRegex(dfupatch.Refused, "trailer"):
            dfupatch.patch(self.data, f"0x{BASE + at:08X} {old} 00000000")
        at = len(self.element) - 40
        old = self.element[at:at + 12].hex()
        with self.assertRaisesRegex(dfupatch.Refused, "trailer"):
            dfupatch.patch(self.data, f"0x{BASE + at:08X} {old} {'00' * 12}")

    def test_a_patch_outside_the_image_is_refused(self):
        with self.assertRaisesRegex(dfupatch.Refused, "outside"):
            dfupatch.patch(self.data, f"0x{BASE - 4:08X} 00 00")

    def test_old_and_new_bytes_of_different_lengths_are_refused(self):
        old = self.element[0x40:0x42].hex()
        with self.assertRaisesRegex(dfupatch.Refused, "length"):
            dfupatch.patch(self.data, f"0x{BASE + 0x40:08X} {old} 00")

    def test_overlapping_patch_lines_are_refused(self):
        a, b = self.element[0x40:0x42].hex(), self.element[0x41:0x43].hex()
        with self.assertRaisesRegex(dfupatch.Refused, "overlap"):
            dfupatch.patch(self.data, f"0x{BASE + 0x40:08X} {a} 0000\n0x{BASE + 0x41:08X} {b} 0000")

    def test_a_malformed_line_is_refused_with_its_line_number(self):
        with self.assertRaisesRegex(dfupatch.Refused, "line 2"):
            dfupatch.patch(self.data, "# fine\nnot a patch line")


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = dfupatch.main(list(argv))
    return code, out.getvalue(), err.getvalue()


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.element = wd_element()
        self.input = self.path("in.dfu", dfuse_file(self.element))

    def path(self, name, content=None):
        path = os.path.join(self.dir.name, name)
        if content is not None:
            with open(path, "wb" if isinstance(content, bytes) else "w") as f:
                f.write(content)
        return path

    def test_verify_passes_a_good_wd_file(self):
        code, out, _ = run("verify", self.input)
        self.assertEqual(code, 0)
        self.assertIn("bit for bit", out)

    def test_verify_refuses_a_tp_file(self):
        code, _, err = run("verify", self.path("tp.dfu", dfuse_file(tp_element())))
        self.assertEqual(code, 1)
        self.assertIn("undecoded", err)

    def test_apply_writes_the_patched_file(self):
        old = self.element[0x40]
        patch = self.path("p.txt", f"0x{BASE + 0x40:08X} {old:02x} {old ^ 0xFF:02x}\n")
        output = self.path("out.dfu")
        code, out, _ = run("apply", self.input, patch, output)
        self.assertEqual(code, 0)
        with open(output, "rb") as f:
            self.assertEqual(dfupatch.parse(f.read()).element[0x40], old ^ 0xFF)
        self.assertIn("trailer CRC", out)

    def test_apply_writes_nothing_when_refused(self):
        patch = self.path("p.txt", f"0x{BASE + 0x40:08X} {self.element[0x40] ^ 1:02x} 00\n")
        output = self.path("out.dfu")
        code, _, err = run("apply", self.input, patch, output)
        self.assertEqual(code, 1)
        self.assertIn("old bytes", err)
        self.assertFalse(os.path.exists(output))

    def test_apply_wont_overwrite_a_file(self):
        patch = self.path("p.txt", "")
        output = self.path("out.dfu", b"keep")
        code, _, err = run("apply", self.input, patch, output)
        self.assertEqual(code, 1)
        with open(output, "rb") as f:
            self.assertEqual(f.read(), b"keep")

    def test_apply_wont_write_inside_the_repository(self):
        # patched images are never committed: the output has to land outside the repo
        output = os.path.join(os.path.dirname(os.path.abspath(dfupatch.__file__)), "patched-test-output.dfu")
        code, _, err = run("apply", self.input, self.path("p.txt", ""), output)
        self.assertEqual(code, 1)
        self.assertIn("outside the repository", err)
        self.assertFalse(os.path.exists(output))


class IgnoreRuleTests(unittest.TestCase):
    def test_vendor_and_patched_images_in_this_folder_are_ignored_by_git(self):
        here = os.path.dirname(os.path.abspath(__file__))
        if not shutil.which("git") or subprocess.run(["git", "-C", here, "rev-parse"], capture_output=True).returncode:
            self.skipTest("not in a git checkout")
        for name in ["stock.dfu", "wd.bin", "dump.bin", "out.patched.dfu", "images/wd.hex", "notes.elf"]:
            path = os.path.join(here, name)
            result = subprocess.run(["git", "-C", here, "check-ignore", "-q", "--no-index", path])
            self.assertEqual(result.returncode, 0, f"{name} isn't ignored")


if __name__ == "__main__":
    unittest.main()
