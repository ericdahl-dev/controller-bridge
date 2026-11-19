"""Tests for drawn_flash.py (#468): the checks the flash-day wizard's drawn path runs before and after each write. Synthetic
files only; no vendor data, nothing sent to a unit.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import contextlib, io, os, tempfile, unittest

import drawn_flash
from test_build_upper_dfu import good_block
from test_dfupatch import dfuse_file, full_wd_element

UPPER, UPPER_SIZE = 0x08080000, 0x80000


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = drawn_flash.main(list(argv))
    return code, out.getvalue(), err.getvalue()


class DrawnFlashTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def path(self, name, content):
        path = os.path.join(self.dir.name, name)
        with open(path, "wb") as f:
            f.write(content)
        return path

    def upper_dfu(self, block=None, address=UPPER):
        return self.path("upper.dfu", dfuse_file(block if block is not None else good_block(), address))

    def owner_dfu(self, address=0x08008000):
        return self.path("owner.dfu", dfuse_file(full_wd_element(), address))

    def assertRefused(self, result, reason):
        code, _, err = result
        self.assertEqual(code, 1)
        self.assertIn(reason, err)


class FilesTests(DrawnFlashTests):
    """Before either typed word: each file is what its step writes, so the two can't be swapped."""

    def test_block_b_and_the_owners_image_in_their_places_pass(self):
        code, out, _ = run("files", self.upper_dfu(), self.owner_dfu())
        self.assertEqual(code, 0)
        self.assertIn("0x08080000", out)
        self.assertIn("0x08008000", out)

    def test_the_two_files_swapped_are_refused(self):
        self.assertRefused(run("files", self.owner_dfu(), self.upper_dfu()), "block B")

    def test_a_block_b_file_anywhere_but_0x08080000_is_refused(self):
        self.assertRefused(run("files", self.upper_dfu(address=0x08008000), self.owner_dfu()), "0x08080000")

    def test_a_block_b_whose_header_doesnt_check_out_is_refused(self):
        bad = bytearray(good_block())
        bad[-1] ^= 1
        self.assertRefused(run("files", self.upper_dfu(bytes(bad)), self.owner_dfu()), "CRC")

    def test_an_owners_image_anywhere_but_0x08008000_is_refused(self):
        self.assertRefused(run("files", self.upper_dfu(), self.owner_dfu(address=0x08080000)), "0x08008000")


class UpperTests(DrawnFlashTests):
    """The read-only read of 0x08080000-0x080FFFFF, judged against B's file: the gate before step 1 and its read-back
    after."""

    def read(self, content):
        return self.path("wd-upper-read.bin", content)

    def test_all_erased_says_erased(self):
        code, out, _ = run("upper", self.upper_dfu(), self.read(b"\xff" * UPPER_SIZE))
        self.assertEqual((code, out.split()[0]), (0, "erased"))

    def test_exactly_this_block_then_erased_says_holds(self):
        block = good_block()
        code, out, _ = run("upper", self.upper_dfu(), self.read(block + b"\xff" * (UPPER_SIZE - len(block))))
        self.assertEqual((code, out.split()[0]), (0, "holds"))

    def test_this_block_with_a_byte_off_is_refused_with_its_address(self):
        read = bytearray(good_block() + b"\xff" * (UPPER_SIZE - len(good_block())))
        read[30] ^= 1
        self.assertRefused(run("upper", self.upper_dfu(), self.read(bytes(read))), "0x0808001E")

    def test_a_half_written_block_says_replace(self):
        # A write cut off part way: this B's first bytes, then erased flash. B is rewritten behind its own word.
        block = good_block()
        read = block[:20] + b"\xff" * (UPPER_SIZE - 20)
        code, out, _ = run("upper", self.upper_dfu(), self.read(read))
        self.assertEqual((code, out.split()[0]), (0, "replace"))

    def test_another_good_block_b_says_replace(self):
        # #501's first B: version 2, the 20-byte header, CRC 0x22B5DF72 from Python's zlib. Every layout change makes
        # a new B (#516), so an older one is replaced, not refused.
        old = bytes.fromhex("44465742" "02000000" "1d000000" "72dfb522" "15000808") + b"123456789"
        code, out, _ = run("upper", self.upper_dfu(), self.read(old + b"\xff" * (UPPER_SIZE - len(old))))
        self.assertEqual((code, out.split()[0]), (0, "replace"))

    def test_another_block_b_with_a_bad_CRC_is_refused(self):
        old = bytearray(bytes.fromhex("44465742" "02000000" "1d000000" "72dfb522" "15000808") + b"123456789")
        old[-1] ^= 1
        self.assertRefused(run("upper", self.upper_dfu(), self.read(bytes(old) + b"\xff" * (UPPER_SIZE - 29))),
                           "CRC")

    def test_another_block_b_with_bytes_after_it_is_refused(self):
        old = bytes.fromhex("44465742" "02000000" "1d000000" "72dfb522" "15000808") + b"123456789"
        read = bytearray(old + b"\xff" * (UPPER_SIZE - len(old)))
        read[0x50000] = 0
        self.assertRefused(run("upper", self.upper_dfu(), self.read(bytes(read))), "0x080D0000")

    def test_anything_else_there_is_refused(self):
        read = bytearray(b"\xff" * UPPER_SIZE)
        read[0x40000] = 0
        self.assertRefused(run("upper", self.upper_dfu(), self.read(bytes(read))), "0x080C0000")

    def test_bytes_after_this_block_that_arent_erased_are_refused(self):
        block = good_block()
        read = bytearray(block + b"\xff" * (UPPER_SIZE - len(block)))
        read[-1] = 0
        self.assertRefused(run("upper", self.upper_dfu(), self.read(bytes(read))), "0x080FFFFF")

    def test_a_read_that_isnt_the_whole_512k_is_refused(self):
        self.assertRefused(run("upper", self.upper_dfu(), self.read(b"\xff" * (UPPER_SIZE - 1))), "524288")


class RewriteTests(DrawnFlashTests):
    """The file step 1 writes over part of a B or an older one (#468). A DfuSe write erases only the sectors its element
    covers, so an older B reaching further would leave its tail: the rewrite carries erased bytes over all of it."""

    def rewrite(self, old):
        read = self.path("wd-upper-read.bin", old + b"\xff" * (UPPER_SIZE - len(old)))
        out = os.path.join(self.dir.name, "rewrite.dfu")
        return run("rewrite", self.upper_dfu(), read, out), out

    def element(self, path):
        import dfupatch
        image = dfupatch.parse(dfupatch.read(path))
        return image.address, image.element

    def test_over_a_longer_older_b_it_is_this_b_then_erased_to_the_old_ones_end(self):
        import struct, zlib
        rest = bytes((i * 5 + 1) & 0xFF for i in range(0x30000 - 16))  # spans sectors 8 and 9
        old = struct.pack("<IIII", 0x42574644, 2, 0x30000, zlib.crc32(rest)) + rest
        (code, _, err), out = self.rewrite(old)
        self.assertEqual(code, 0, err)
        address, element = self.element(out)
        block = good_block()
        self.assertEqual(address, UPPER)
        self.assertEqual(len(element), 0x30000)
        self.assertEqual(element[:len(block)], block)
        self.assertEqual(set(element[len(block):]), {0xFF})

    def test_over_part_of_this_b_it_is_this_b(self):
        (code, _, err), out = self.rewrite(good_block()[:20])
        self.assertEqual(code, 0, err)
        self.assertEqual(self.element(out), (UPPER, good_block()))

    def test_with_nothing_to_rewrite_it_is_refused(self):
        for read in (b"", good_block()):
            with self.subTest(len(read)):
                (code, _, err), out = self.rewrite(read)
                self.assertEqual(code, 1)
                self.assertIn("nothing to rewrite", err)
                self.assertFalse(os.path.exists(out))


if __name__ == "__main__":
    unittest.main()
