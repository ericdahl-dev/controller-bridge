#!/usr/bin/env python3
"""Pins the v1.1 release checklist and the TestFlight What to Test it ships with. No network.
Run: python3 -I scripts/test_release_docs.py"""
import os, re, sys, unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testflight_distribute as td

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


class ReleaseChecklist(unittest.TestCase):
    def test_steps_in_order(self):
        steps = re.findall(r"^## (\d+)\. (.+)$", read("docs/RELEASE-1.1.md"), re.M)
        self.assertEqual(steps, [
            ("1", "Hardware spike: upload timing"),
            ("2", "Jog display hardware checklist"),
            ("3", "Turn the jog display on by default"),
            ("4", "CHANGELOG"),
            ("5", "TestFlight What to Test"),
            ("6", "Internal build"),
            ("7", "External build"),
            ("8", "Site"),
            ("9", "App Store listing"),
            ("10", "After the release"),
        ])

    def test_version_and_tags(self):
        doc = read("docs/RELEASE-1.1.md")
        self.assertIn('git tag -a v1.1.0 -m "Release 1.1.0"', doc)
        self.assertIn("[external]", doc)
        self.assertIn("## 1.1.0", doc)  # the ready-to-paste CHANGELOG block

    def test_site_step_links_the_held_pr(self):
        doc = read("docs/RELEASE-1.1.md")
        site = doc[doc.index("## 8. Site"):doc.index("## 9.")]
        self.assertIn("https://github.com/ericdahl-dev/deckbridge/pull/300", site)


class WhatToTest(unittest.TestCase):
    def setUp(self):
        self.text = td.what_to_test(read("docs/TESTFLIGHT.md"))

    def test_fits_app_store_connect(self):
        self.assertLessEqual(len(self.text), 4000)

    def test_is_for_1_1(self):
        self.assertTrue(self.text.startswith("DeckBridge 1.1.0"), self.text[:60])

    def test_names_what_to_try(self):
        for phrase in ["jog display", "Diagnostics › Jog display", "subscription", "Help add a controller"]:
            self.assertIn(phrase, self.text)

    def test_never_offers_the_led_test(self):
        self.assertNotIn("Test LEDs", self.text)
        self.assertNotIn("LED test", self.text)


if __name__ == "__main__":
    unittest.main()
