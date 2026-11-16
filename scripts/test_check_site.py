#!/usr/bin/env python3
"""Tests for scripts/check_site.py on tiny sites written to a temporary folder. No network.
Run: python3 -I scripts/test_check_site.py"""
import os, sys, tempfile, unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_site


def page(title="DeckBridge", description="A bridge.", body="", head=""):
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{title}</title>'
            f'<meta name="description" content="{description}">{head}</head><body>{body}</body></html>')


GOOD = {
    "index.html": page(head='<link rel="stylesheet" href="style.css"><link rel="icon" href="img/icon.png">',
                       body='<a href="support/">Support</a> <a href="privacy/">Privacy</a> <img src="img/icon.png" alt="">'
                            ' <a href="https://testflight.apple.com/join/XXXX">TestFlight</a>'),
    "support/index.html": page(body='<a href="../">Home</a> <a href="../privacy/#network">Network</a>'),
    "privacy/index.html": page(body='<h2 id="network">Network</h2><p>DeckBridge collects no data.</p>'),
    "style.css": '@font-face { font-family: Inter; src: url("fonts/Inter-Regular.ttf"); } body { color: #EDEDEA; }',
    "fonts/Inter-Regular.ttf": "font",
    "img/icon.png": "png",
}


class CheckSiteTests(unittest.TestCase):
    def site(self, changes=None, remove=()):
        files = dict(GOOD)
        files.update(changes or {})
        for name in remove:
            files.pop(name)
        root = tempfile.mkdtemp()
        for name, text in files.items():
            path = os.path.join(root, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(text)
        return root

    def test_a_good_site_passes(self):
        self.assertEqual(check_site.problems(self.site()), [])

    def test_a_missing_page_fails(self):
        self.assertEqual(check_site.problems(self.site(remove=["privacy/index.html"])),
                         ["privacy/index.html: missing",
                          "index.html: link to privacy/ doesn't resolve",
                          "support/index.html: link to ../privacy/#network doesn't resolve"])

    def test_a_broken_link_or_asset_fails(self):
        root = self.site({"support/index.html": page(body='<a href="../faq/">FAQ</a> <img src="../img/nope.png" alt="">')})
        self.assertEqual(check_site.problems(root), ["support/index.html: link to ../faq/ doesn't resolve",
                                                     "support/index.html: link to ../img/nope.png doesn't resolve"])

    def test_a_css_url_that_doesnt_resolve_fails(self):
        root = self.site({"style.css": '@font-face { src: url("fonts/Missing.ttf"); }'})
        self.assertEqual(check_site.problems(root), ["style.css: link to fonts/Missing.ttf doesn't resolve"])

    def test_external_resources_fail_but_external_links_dont(self):
        root = self.site({
            "index.html": page(head='<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Inter">',
                               body='<img src="//cdn.example.com/a.png" alt=""> <script src="http://x.example/t.js"></script>'
                                    ' <a href="https://testflight.apple.com/join/XXXX">ok</a>'
                                    ' <a href="support/">s</a> <a href="privacy/">p</a>'),
            "style.css": '@import url("https://fonts.example/x.css"); body { background: url(https://x.example/bg.png); }',
        })
        self.assertEqual(check_site.problems(root), [
            "index.html: loads https://fonts.googleapis.com/css?family=Inter from another site",
            "index.html: loads //cdn.example.com/a.png from another site",
            "index.html: loads http://x.example/t.js from another site",
            "style.css: loads https://fonts.example/x.css from another site",
            "style.css: loads https://x.example/bg.png from another site",
        ])

    def test_a_page_without_a_title_or_description_fails(self):
        root = self.site({"support/index.html": page(title="", description="", body='<a href="../">Home</a>')})
        self.assertEqual(check_site.problems(root), ["support/index.html: no <title>",
                                                     "support/index.html: no meta description"])

    def test_the_privacy_page_must_say_no_data_is_collected(self):
        root = self.site({"privacy/index.html": page(body="<p>We care about your privacy.</p>")})
        self.assertEqual(check_site.problems(root), ['privacy/index.html: doesn\'t say "collects no data"'])

    def test_a_third_party_logo_file_fails(self):
        root = self.site({"img/denon-logo.svg": "<svg/>", "img/Syndicate_logo.png": "png"})
        self.assertEqual(check_site.problems(root), ["img/Syndicate_logo.png: looks like another company's logo",
                                                     "img/denon-logo.svg: looks like another company's logo"])


    def test_titles_and_headings_dont_use_other_companies_names(self):
        root = self.site({
            "support/index.html": page(title="Syndicate Bridge Support", body='<h1>Denon <em>Controller</em> Help</h1><a href="../">Home</a>'),
            "privacy/index.html": page(body="<h1>Privacy</h1><p>Works with Syndicate. DeckBridge collects no data.</p>"),
        })
        self.assertEqual(check_site.problems(root), ['support/index.html: the <title> names Syndicate',
                                                     'support/index.html: the <h1> names Denon'])

    def test_a_site_over_two_megabytes_fails(self):
        root = self.site({"img/huge.png": "x" * 2_100_000})
        self.assertEqual(check_site.problems(root), ["the site is 2.1 MB, over 2 MB"])


if __name__ == "__main__":
    unittest.main()
