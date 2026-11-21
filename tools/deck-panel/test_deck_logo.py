#!/usr/bin/env python3
"""Tests for deck_logo.py (#651): the waiting screen's logo is design/icon/icon-1-deck-ring.svg, drawn from the SVG's
own numbers, and src/deck_logo.c is what the generator makes from it now.
Run: python3 -I tools/deck-panel/test_deck_logo.py. After an icon change: python3 -I tools/deck-panel/deck_logo.py"""
import importlib.util, os, re, sys, tempfile, unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SVG = os.path.join(HERE, "..", "..", "design", "icon", "icon-1-deck-ring.svg")
C_FILE = os.path.join(HERE, "src", "deck_logo.c")


def load_generator():
    spec = importlib.util.spec_from_file_location("deck_logo", os.path.join(HERE, "deck_logo.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gen = load_generator()
LOGO = gen.render(SVG)

# The icon's colors as LVGL stores them in RGB565 (lv_color_hex: the top 5, 6, 5 bits), worked out by hand.
GRAY_ARC, GOLD_ARC, COPPER_ARC, TEAL_ARC = 0x6B8E, 0xEE6C, 0xC3A9, 0x6493
NEEDLE_AND_HUB, INNER_DISC, HOLE, BLACK = 0xD6BA, 0x18E3, 0x10A2, 0x0000


def at(logo, radius, degrees):
    """The pixel `radius` SVG units from the middle, at `degrees` (0 is right, 90 is down: the SVG's y is down)."""
    import math
    x = logo.size / 2 + radius * logo.scale * math.cos(math.radians(degrees))
    y = logo.size / 2 + radius * logo.scale * math.sin(math.radians(degrees))
    return logo.pixels[int(y) * logo.size + int(x)]


class DeckLogoTests(unittest.TestCase):
    def test_the_committed_image_is_what_the_svg_makes(self):
        with open(C_FILE) as f:
            committed = f.read()
        self.assertEqual(committed, gen.c_source(LOGO),
                         "src/deck_logo.c is stale: run python3 -I tools/deck-panel/deck_logo.py")

    def test_it_is_192_px_square_opaque_rgb565_in_flash(self):
        self.assertEqual(LOGO.size, 192)
        self.assertEqual(len(LOGO.pixels), 192 * 192)
        with open(C_FILE) as f:
            text = f.read()
        self.assertIn(".cf = LV_COLOR_FORMAT_RGB565,", text)
        self.assertIn(".magic = LV_IMAGE_HEADER_MAGIC,", text)
        self.assertIn(".w = 192,", text)
        self.assertIn(".h = 192,", text)
        self.assertIn(".stride = 384,", text)
        self.assertIn(".data_size = 73728,", text)
        self.assertIn("static const uint8_t deck_logo_map[73728]", text)
        self.assertIn("const lv_image_dsc_t deck_logo = {", text)
        self.assertEqual(len(re.findall(r"0x[0-9a-f]{2},", text)), 73728)

    def test_the_whole_logo_fits_with_black_corners(self):
        # The needle's tip reaches 310 units out, past the arcs (300): the crop is the farthest shape.
        self.assertEqual(LOGO.pixels[0], BLACK)
        self.assertEqual(LOGO.pixels[-1], BLACK)
        edge = [LOGO.pixels[i] for i in range(LOGO.size)] + [LOGO.pixels[i * LOGO.size] for i in range(LOGO.size)]
        self.assertEqual(set(edge), {BLACK}, "a shape touches the top or left edge: it is cut off")
        self.assertAlmostEqual(LOGO.scale, 192 / 620, places=9)

    def test_the_four_arcs_are_the_svgs_colors_clockwise_from_top_right(self):
        self.assertEqual(at(LOGO, 262, -30), GRAY_ARC)
        self.assertEqual(at(LOGO, 262, 45), GOLD_ARC)
        self.assertEqual(at(LOGO, 262, 135), COPPER_ARC)
        self.assertEqual(at(LOGO, 262, -135), TEAL_ARC)
        # The gaps between them, at the four compass points, are the background.
        for degrees in (0, 90, 180, -90):
            self.assertEqual(at(LOGO, 262, degrees), BLACK, degrees)

    def test_the_disc_needle_hub_and_hole(self):
        self.assertEqual(at(LOGO, 0, 0), HOLE)
        self.assertEqual(at(LOGO, 50, 90), NEEDLE_AND_HUB)  # hub
        self.assertEqual(at(LOGO, 150, 90), INNER_DISC)
        # The needle, turned 40 degrees clockwise from straight up: between the disc (206) and the arcs (224).
        self.assertEqual(at(LOGO, 215, -50), NEEDLE_AND_HUB)
        self.assertEqual(at(LOGO, 215, -90), BLACK)

    def test_edges_are_antialiased(self):
        self.assertGreater(len(set(LOGO.pixels)), 20)

    def test_the_numbers_come_from_the_svg(self):
        with open(SVG) as f:
            svg = f.read()
        changed = svg.replace("#ECCF65", "#FF0000").replace("rotate(40 512 512)", "rotate(130 512 512)")
        self.assertNotEqual(changed, svg)
        with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
            f.write(changed)
        try:
            logo = gen.render(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(at(logo, 262, 45), 0xF800)
        self.assertEqual(at(logo, 215, -50), BLACK)
        self.assertEqual(at(logo, 215, 40), NEEDLE_AND_HUB)


if __name__ == "__main__":
    unittest.main()
