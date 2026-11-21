"""Tests for add_panel_image.py (#686): the build step that puts a deck panel image into the updater's catalog."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("add_panel_image.py")
LC6000 = [{"wd": "00.50", "tp": "00.31", "entries": [{"kind": "patch", "chip": "wd", "file": "lc6000/x.patch"}]}]


def run(*args):
    return subprocess.run([sys.executable, "-I", str(SCRIPT), *map(str, args)], capture_output=True, text=True)


class AddPanelImage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.catalog = root / "Resources"
        self.catalog.mkdir()
        (self.catalog / "catalog.json").write_text(json.dumps({"panel": [], "lc6000": LC6000}))
        self.image = root / "firmware.bin"
        self.image.write_bytes(b"\xe9" + bytes(range(255)) * 8)

    def tearDown(self):
        self.tmp.cleanup()

    def listed(self):
        return json.loads((self.catalog / "catalog.json").read_text())

    def test_the_image_is_copied_in_and_listed_with_its_version_and_sha(self):
        result = run("--catalog", self.catalog, "--image", self.image, "--version", "1.0.0", "--sha", "1d0683f")
        self.assertEqual(result.returncode, 0, result.stderr)
        listed = self.listed()
        self.assertEqual(listed["panel"], [{"version": "1.0.0", "sha": "1d0683f", "image": "panel/deck-panel-1.0.0-1d0683f.bin"}])
        self.assertEqual(listed["lc6000"], LC6000)
        self.assertEqual((self.catalog / "panel/deck-panel-1.0.0-1d0683f.bin").read_bytes(), self.image.read_bytes())


if __name__ == "__main__":
    unittest.main()
