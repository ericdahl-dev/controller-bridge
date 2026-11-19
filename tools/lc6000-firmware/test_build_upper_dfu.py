"""Tests for build_upper_dfu.py (#501): block B's own DfuSe file at 0x08080000, built only with the owner's read-only
read of the upper flash as proof that sector 8 exists and is empty. Synthetic data only, no vendor bytes.
Run from the repo root: python3 -I -m unittest discover tools/lc6000-firmware"""
import contextlib, io, os, struct, tempfile, unittest

import build_upper_dfu
import dfupatch

UPPER = 0x08080000
PROOF_SIZE = 512 * 1024


def good_block():
    """The same B as the C header tests (arm/test/test_hook.c): its CRC 0x22B5DF72 is zlib's, worked out apart."""
    return struct.pack("<IIIII", 0x42574644, 1, 29, 0x22B5DF72, 0x08080015) + b"123456789"


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = build_upper_dfu.main(list(argv))
    return code, out.getvalue(), err.getvalue()


class BuildUpperDfuTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def path(self, name, content=None):
        path = os.path.join(self.dir.name, name)
        if content is not None:
            with open(path, "wb") as f:
                f.write(content)
        return path

    def build(self, block=None, proof=None):
        blob = self.path("upper.bin", block if block is not None else good_block())
        read = self.path("wd-upper-512k.bin", proof if proof is not None else b"\xff" * PROOF_SIZE)
        output = self.path("upper.dfu")
        code, out, err = run(blob, output, "--proof", read)
        return code, out, err, output

    def test_a_good_block_with_the_proof_becomes_one_element_at_0x08080000(self):
        code, _, err, output = self.build()
        self.assertEqual(code, 0, err)
        image = dfupatch.parse(dfupatch.read(output))
        self.assertEqual(image.address, UPPER)
        self.assertEqual(image.element, good_block())

    def assertRefused(self, result, reason):
        code, out, err, output = result
        self.assertEqual(code, 1)
        self.assertIn(reason, err)
        self.assertFalse(os.path.exists(output), "nothing is written when refused")

    def test_without_the_proof_it_is_refused(self):
        blob = self.path("upper.bin", good_block())
        output = self.path("upper.dfu")
        code, out, err = run(blob, output)
        self.assertRefused((code, out, err, output), "--proof")


    def test_a_proof_that_isnt_the_whole_512k_read_is_refused(self):
        self.assertRefused(self.build(proof=b"\xff" * (PROOF_SIZE - 1)), "524288")
        self.assertRefused(self.build(proof=b""), "524288")


if __name__ == "__main__":
    unittest.main()
