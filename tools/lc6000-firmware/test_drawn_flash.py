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

    def test_a_half_written_block_is_refused_where_it_stops(self):
        # A write cut off part way: this B's first bytes, then erased flash.
        block = good_block()
        read = block[:20] + b"\xff" * (UPPER_SIZE - 20)
        self.assertRefused(run("upper", self.upper_dfu(), self.read(read)), "0x08080014")

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


if __name__ == "__main__":
    unittest.main()
